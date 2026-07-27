// desktop-notify.js — sends real Ubuntu desktop notifications via D-Bus when
// a session finishes, errors, or needs a permission decision, and jumps back
// to the originating tmux pane when one is clicked.
//
// OpenCode's built-in attention.notifications relies on the terminal catching
// OSC 9/99/777 escape codes. Alacritty implements none of them
// (github.com/alacritty/alacritty#7105), so those notifications never
// surface here. This bypasses the terminal entirely and talks to GNOME
// Shell's notification service directly via gdbus/dbus-monitor.
//
// notify-send has no way to attach a click action, so notifications are sent
// with a raw `Notify` call carrying a "default" action (the freedesktop spec
// reserves that key for the action invoked by clicking the notification
// body). Catching the click requires watching the bus for the resulting
// ActionInvoked signal - but it's emitted by GNOME Shell's own connection,
// not by whatever process owns the "org.freedesktop.Notifications" name (on
// this machine those are two different, unrelated D-Bus connections), so
// `gdbus monitor --dest org.freedesktop.Notifications` silently misses it.
// dbus-monitor filtered on the interface/member instead, with no --dest
// restriction, is what actually sees it (confirmed by capturing a real click
// with an unfiltered dbus-monitor session).
import { appendFileSync, readFileSync, unlinkSync } from "fs"
import { spawn } from "bun"

const DEBUG_LOG = "/tmp/opencode-desktop-notify-debug.log"
function debug(msg) {
  try {
    appendFileSync(DEBUG_LOG, `${new Date().toISOString()} ${msg}\n`)
  } catch {}
}

const JUMP_SCRIPT = `${process.env.HOME}/.tmux/notify-jump.sh`
const SUMMARY_LIMIT = 220

function urgencyByte(urgency) {
  if (urgency === "critical") return 2
  if (urgency === "low") return 0
  return 1
}

function shortenPath(dir) {
  const home = process.env.HOME
  return home && dir?.startsWith(home) ? `~${dir.slice(home.length)}` : dir
}

export const DesktopNotifyPlugin = async ({ $, directory }) => {
  const pane = process.env.TMUX_PANE
  if (!pane) return {}

  const active = new Set()
  const errored = new Set()
  const permissions = new Set()
  const ownedIds = new Set()
  const projectLabel = shortenPath(directory)

  // The generated client's session.get/session.messages methods are broken
  // on this opencode version - they always send a literal unsubstituted
  // "{id}" path segment no matter what key the input object uses, and
  // PluginInput.serverUrl points at an unrelated shared server rather than
  // this instance's own data (confirmed by testing both against real
  // sessions). `opencode export` reads straight from local storage, sidestepping both.
  async function exportSession(sessionID) {
    // Long sessions export tens of MB of JSON, and capturing that through
    // Bun's shell `.text()` silently truncates around ~200KB (confirmed on a
    // real 2000+ message session - it cut off mid-object and failed to
    // parse). Redirecting to a file and reading it back avoids that limit.
    const tmpFile = `/tmp/opencode-desktop-notify-export-${sessionID}-${process.pid}.json`
    try {
      await $`opencode export ${sessionID} > ${tmpFile}`.nothrow().quiet()
      return JSON.parse(readFileSync(tmpFile, "utf8"))
    } catch (error) {
      debug(`exportSession failed sessionID=${sessionID} error=${error}`)
      return undefined
    } finally {
      try {
        unlinkSync(tmpFile)
      } catch {}
    }
  }

  function lastAssistantText(messages) {
    const assistant = (messages ?? []).filter((m) => m.info?.role === "assistant")
    assistant.sort((a, b) => (b.info.time?.created ?? 0) - (a.info.time?.created ?? 0))
    const latest = assistant[0]
    if (!latest) return undefined
    const textParts = latest.parts.filter((p) => p.type === "text" && p.text?.trim())
    const last = textParts[textParts.length - 1]
    if (!last) return undefined
    const flat = last.text.replace(/\s+/g, " ").trim()
    return flat.length > SUMMARY_LIMIT ? `${flat.slice(0, SUMMARY_LIMIT)}…` : flat
  }

  async function tmuxContext() {
    try {
      const format = "#{session_name}\t#{window_name}"
      const text = await $`tmux display-message -p -t ${pane} ${format}`.nothrow().quiet().text()
      const [sessionName, windowName] = text.trim().split("\t")
      if (!sessionName) return undefined
      return `${sessionName}:${windowName}`
    } catch (error) {
      debug(`tmuxContext failed: ${error}`)
      return undefined
    }
  }

  // GNOME renders `summary` and `body` as two separate lines but with
  // identical (non-bold) styling here - confirmed by testing - and collapses
  // embedded newlines within a single field down to one line rather than
  // wrapping them. So the two real text slots are summary and body, and
  // `body-markup` (confirmed via GetCapabilities) is the only way to get any
  // visual emphasis: put "where" (tmux + project) in summary, and a bolded
  // label plus the "what" (message snippet or title) in body.
  function whereLine(context, status) {
    const where = [context, projectLabel].filter(Boolean).join(" · ")
    return where ? `${where} — ${status}` : status
  }

  function escapeMarkup(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  function whatBody(label, text) {
    return `<b>${escapeMarkup(label)}:</b> ${escapeMarkup(text)}`
  }

  async function send(urgency, summary, body) {
    const hints = `{'urgency': <byte ${urgencyByte(urgency)}>}`
    try {
      const result = await $`gdbus call -e -d org.freedesktop.Notifications -o /org/freedesktop/Notifications -m org.freedesktop.Notifications.Notify -- ${"opencode"} ${0} ${""} ${summary} ${body} ${"['default', '']"} ${hints} ${-1}`
        .nothrow()
        .quiet()
        .text()
      const match = result.match(/uint32 (\d+)/)
      const id = match ? Number(match[1]) : undefined
      debug(`notify urgency=${urgency} summary=${summary} body=${body} id=${id}`)
      if (id !== undefined) ownedIds.add(id)
    } catch (error) {
      debug(`notify failed: ${error}`)
    }
  }

  // One persistent listener per opencode instance (one per tmux pane),
  // watching for clicks on notifications *this* instance sent.
  let monitor
  try {
    monitor = spawn({
      cmd: [
        "dbus-monitor",
        "--session",
        "type='signal',interface='org.freedesktop.Notifications',member='ActionInvoked'",
        "type='signal',interface='org.freedesktop.Notifications',member='NotificationClosed'",
      ],
      stdout: "pipe",
      stderr: "ignore",
    })
    ;(async () => {
      const reader = monitor.stdout.getReader()
      const decoder = new TextDecoder()
      let buffer = ""
      let pendingKind = null
      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          buffer += decoder.decode(value, { stream: true })
          let idx
          while ((idx = buffer.indexOf("\n")) >= 0) {
            const line = buffer.slice(0, idx)
            buffer = buffer.slice(idx + 1)
            const header = line.match(/member=(ActionInvoked|NotificationClosed)/)
            if (header) {
              pendingKind = header[1]
              continue
            }
            if (!pendingKind) continue
            const idMatch = line.match(/uint32\s+(\d+)/)
            if (!idMatch) continue
            const id = Number(idMatch[1])
            const kind = pendingKind
            pendingKind = null
            if (!ownedIds.has(id)) continue
            if (kind === "NotificationClosed") {
              ownedIds.delete(id)
              continue
            }
            ownedIds.delete(id)
            debug(`click id=${id} -> jumping pane=${pane}`)
            await $`${JUMP_SCRIPT} ${pane}`.nothrow().quiet()
          }
        }
      } catch (error) {
        debug(`monitor read loop ended: ${error}`)
      }
    })()
  } catch (error) {
    debug(`failed to start dbus-monitor: ${error}`)
  }

  return {
    dispose: async () => {
      try {
        monitor?.kill()
      } catch {}
    },
    event: async ({ event }) => {
      const sessionID = event.properties?.sessionID

      if (event.type === "session.status") {
        const status = event.properties.status.type
        if (status === "busy" || status === "retry") {
          active.add(sessionID)
          errored.delete(sessionID)
        }
        return
      }

      if (event.type === "session.idle") {
        if (!active.has(sessionID)) return
        active.delete(sessionID)
        if (errored.delete(sessionID)) return
        const [exported, context] = await Promise.all([exportSession(sessionID), tmuxContext()])
        const title = exported?.info?.title
        const snippet = lastAssistantText(exported?.messages)
        await send("normal", whereLine(context, "done"), whatBody(title ?? "Done", snippet ?? title ?? "Session finished"))
        return
      }

      if (event.type === "session.error") {
        if (!sessionID || !active.has(sessionID)) return
        errored.add(sessionID)
        const [exported, context] = await Promise.all([exportSession(sessionID), tmuxContext()])
        await send("critical", whereLine(context, "error"), whatBody("Error", exported?.info?.title ?? "Session hit an error"))
        return
      }

      if (event.type === "permission.updated") {
        const id = event.properties.id
        if (permissions.has(id)) return
        permissions.add(id)
        const [exported, context] = await Promise.all([exportSession(event.properties.sessionID), tmuxContext()])
        await send(
          "critical",
          whereLine(context, "needs permission"),
          whatBody("Permission", exported?.info?.title ?? event.properties.title ?? "Permission requested"),
        )
        return
      }

      if (event.type === "permission.replied") {
        permissions.delete(event.properties.permissionID)
      }
    },
  }
}
