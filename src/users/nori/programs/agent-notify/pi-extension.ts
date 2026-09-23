// Managed by home-manager (nori.agentNotify) — do not edit in place.
// Pings the agents ntfy topic when Pi settles (turn done, awaiting the
// operator). `agent_settled` is Pi's "won't continue on its own" signal;
// Pi ships no built-in permission/question prompt (those are extensions),
// so stop is the honest halt coverage — same as Codex's notify.
import { execFile } from "node:child_process"

export default function (pi: {
  on: (event: string, handler: () => Promise<void> | void) => void
}) {
  pi.on("agent_settled", () => {
    execFile("agent-notify", ["pi", "stop", JSON.stringify({ cwd: process.cwd() })])
  })
}
