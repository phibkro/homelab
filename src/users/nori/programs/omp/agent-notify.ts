// Managed by Home Manager — do not edit the installed copy.
//
// OMP's HookAPI can observe settled turns and tool execution, but approval
// requests are exposed only by ExtensionAPI. Keep the three operator-attention
// signals in one small adapter to the harness-independent agent-notify command.
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent"

type AttentionEvent = "stop" | "permission" | "question"

// Only the root interactive session carries a UI; subagent sessions run
// headless. Same discriminator herdr-omp-agent-state.ts uses — without it,
// every finishing subagent pings the operator's phone.
function isRootSession(ctx: unknown): boolean {
  return (ctx as { hasUI?: boolean } | undefined)?.hasUI === true
}

function notify(event: AttentionEvent, cwd: string): void {
  const child = Bun.spawn(
    ["agent-notify", "omp", event, JSON.stringify({ cwd })],
    {
      cwd,
      stdin: "ignore",
      stdout: "ignore",
      stderr: "ignore",
    },
  )

  // Notifications must never hold up or fail an agent turn.
  void child.exited.catch(() => undefined)
}

export default function agentNotify(pi: ExtensionAPI): void {
  pi.on("agent_end", (event, ctx) => {
    if (!isRootSession(ctx)) return
    if (event.willContinue) return
    notify("stop", ctx.cwd)
  })

  pi.on("tool_approval_requested", (_event, ctx) => {
    if (!isRootSession(ctx)) return
    notify("permission", ctx.cwd)
  })

  pi.on("tool_execution_start", (event, ctx) => {
    if (!isRootSession(ctx)) return
    if (event.toolName === "ask") notify("question", ctx.cwd)
  })
}
