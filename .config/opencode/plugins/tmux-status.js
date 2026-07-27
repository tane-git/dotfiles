// tmux-status.js — flags this pane's tmux window with @agent-waiting while
// opencode is idle (waiting on you) and @agent-busy while it's actively
// working, each cleared when the other is set. Read by window-status-format
// in .tmux.conf to show an indicator on the tab. No-ops outside tmux.
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
  // writes onto one promise chain forces them to land in arrival order, and
  // combining both options into one tmux invocation makes each write atomic.
  let queue = Promise.resolve()
  const setFlags = (waiting, busy) => {
    queue = queue.then(() =>
      $`tmux set-option -w -t ${pane} @agent-waiting ${waiting} \; set-option -w -t ${pane} @agent-busy ${busy}`
        .nothrow()
        .quiet(),
    )
    return queue
  }

  return {
    event: async ({ event }) => {
      debug(`event type=${event.type} properties=${JSON.stringify(event.properties ?? {})}`)
      if (event.type === "session.idle") {
        await setFlags("1", "0")
      } else if (event.type === "session.status" && event.properties.status.type === "busy") {
        await setFlags("0", "1")
      }
    },
  }
}
