// Managed by Home Manager through the omp module — do not edit the installed copy.
//
// projects-tier: OMP extension entry. The package's skills/ and agents/ are
// discovered by OMP from the same extension root; this module adds the
// repository instruction-chain hook (see repo-context.ts).
import { homedir } from "node:os"
import { join } from "node:path"
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent"
import { CONTEXT_MESSAGE_TYPE, ChainTracker, PROJECTS_ROOT } from "./repo-context.ts"

function userInstructions(pi: ExtensionAPI): string {
  // `pi.pi` exposes the host package's exports; `getAgentDir` honours
  // profiles and PI_CODING_AGENT_DIR.
  const host: unknown = pi.pi
  const getAgentDir =
    typeof host === "object" && host !== null && "getAgentDir" in host ? host.getAgentDir : undefined
  const agentDir =
    typeof getAgentDir === "function"
      ? String(getAgentDir())
      : (process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".omp", "agent"))
  return join(agentDir, "AGENTS.md")
}

function systemPromptText(ctx: ExtensionContext): string {
  const prompt: unknown = ctx.getSystemPrompt()
  if (typeof prompt === "string") return prompt
  if (Array.isArray(prompt)) return prompt.filter((part): part is string => typeof part === "string").join("\n\n")
  return ""
}

export default function projectsTier(pi: ExtensionAPI): void {
  const tracker = new ChainTracker({ projectsRoot: PROJECTS_ROOT, userInstructions: userInstructions(pi) })
  // A new or switched session holds none of the earlier injections. Within a
  // session the `context` event shows which injections the model still has,
  // which covers compaction, /clear, branching, and resuming.
  pi.on("session_start", () => tracker.reset())
  pi.on("session_switch", () => tracker.reset())
  pi.on("turn_start", () => tracker.onTurnStart())
  pi.on("context", (event) => tracker.onContext(event.messages))
  pi.on("message_end", (event) => tracker.onMessage(event.message))

  pi.on("tool_call", (event, ctx) => {
    let plan
    try {
      plan = tracker.onToolCall(event.toolName, event.input, ctx.cwd, () => systemPromptText(ctx))
    } catch (error) {
      // The hook is advisory infrastructure: a defect here must not block the
      // operator's tool calls (OMP treats a throwing tool_call handler as a block).
      pi.logger?.warn?.("projects-tier: repository context hook failed", { error: String(error) })
      return undefined
    }
    for (const injection of plan.injections) {
      pi.sendMessage(
        {
          customType: CONTEXT_MESSAGE_TYPE,
          content: injection.text,
          display: false,
          details: injection.details,
          attribution: "agent",
        },
        { deliverAs: "aside" },
      )
      if (ctx.hasUI) ctx.ui.notify(`projects-tier: injected instructions for ${injection.details.repo}`, "info")
    }
    return plan.block === undefined ? undefined : { block: true, reason: plan.block }
  })
}
