// Managed by home-manager (nori.agentNotify) — do not edit in place.
// Pings the agents ntfy topic (via agent-notify → nori-alert) whenever
// OpenCode halts awaiting the operator. One generic `event` hook, switched
// on event.type (the per-event hook keys don't exist — see the research in
// the 2026-07-18 session).
import type { Plugin } from "@opencode-ai/plugin"

export const NtfyAgentNotify: Plugin = async ({ $, directory }) => {
  const notify = (event: string) =>
    $`agent-notify opencode ${event} ${JSON.stringify({ cwd: directory })}`
      .quiet()
      .nothrow()

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.idle":
          await notify("stop")
          break
        case "permission.v2.asked":
          await notify("permission")
          break
        case "question.v2.asked":
          await notify("question")
          break
      }
    },
  }
}
