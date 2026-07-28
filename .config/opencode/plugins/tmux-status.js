// tmux-status.js — flags this pane's tmux window with @agent-state to show
// what opencode is doing: busy (working), done (finished, waiting on you),
// input (needs an answer to a question/permission), or error (turn failed).
// Empty when nothing notable. Read by window-status-format in .tmux.conf to
// draw the matching glyph on the tab. No-ops outside tmux.
import { appendFileSync } from "fs"

const DEBUG_LOG = "/tmp/opencode-tmux-status-debug.log"
function debug(msg) {
  try {
    appendFileSync(DEBUG_LOG, `${new Date().toISOString()} ${msg}\n`)
  } catch {}
}

export const TmuxStatusPlugin = async ({ $ }) => {
  const pane = process.env.TMUX_PANE
  debug(`plugin loaded pid=${process.pid} TMUX_PANE=${pane ?? "(unset)"}`)
  if (!pane) return {}

  // Events can arrive faster than each tmux round-trip completes (opencode
  // doesn't wait for a hook to finish before firing the next event), so two
  // overlapping calls can interleave and leave a stale flag stuck. Queuing
  // writes onto one promise chain forces them to land in arrival order. A
  // single option is set atomically, so there's no window where two flags
  // disagree about the state.
  let queue = Promise.resolve()
  const setState = (state) => {
    queue = queue.then(() => $`tmux set-option -w -t ${pane} @agent-state ${state}`.nothrow().quiet())
    return queue
  }

  return {
    event: async ({ event }) => {
      debug(`event type=${event.type} properties=${JSON.stringify(event.properties ?? {})}`)
      if (event.type === "session.status") {
        const status = event.properties.status.type
        if (status === "busy" || status === "retry") await setState("busy")
      } else if (event.type === "session.error") {
        await setState("error")
      } else if (event.type === "question.asked" || event.type === "permission.asked") {
        await setState("input")
      } else if (event.type === "session.idle") {
        await setState("done")
      }
    },
  }
}
