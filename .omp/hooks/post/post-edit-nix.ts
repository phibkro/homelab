import type { HookAPI } from "@oh-my-pi/pi-coding-agent/extensibility/hooks"

async function repositoryRoot(cwd: string): Promise<string | undefined> {
  const process = Bun.spawn(["git", "-C", cwd, "rev-parse", "--show-toplevel"], {
    stdin: "ignore",
    stdout: "pipe",
    stderr: "ignore",
  })
  if ((await process.exited) !== 0) return undefined
  return (await new Response(process.stdout).text()).trim() || undefined
}

function diagnosticFrom(output: string): string | undefined {
  if (!output) return undefined
  try {
    const parsed = JSON.parse(output) as {
      hookSpecificOutput?: { additionalContext?: unknown }
    }
    const diagnostic = parsed.hookSpecificOutput?.additionalContext
    return typeof diagnostic === "string" ? diagnostic : output
  } catch {
    return output
  }
}

export default function postEditNix(pi: HookAPI): void {
  pi.on("tool_result", async (event, ctx) => {
    if (event.isError || (event.toolName !== "edit" && event.toolName !== "write")) {
      return
    }

    const path = event.input.path ?? event.input.file_path
    if (typeof path !== "string" || !path.endsWith(".nix")) return

    const root = await repositoryRoot(ctx.cwd)
    if (!root) return

    const process = Bun.spawn(
      ["bash", `${root}/tools/hooks/post-edit-nix.sh`],
      {
        cwd: root,
        env: { ...Bun.env, CLAUDE_PROJECT_DIR: root },
        stdin: new Blob([JSON.stringify({ tool_input: { file_path: path } })]),
        stdout: "pipe",
        stderr: "pipe",
      },
    )

    const [status, stdout, stderr] = await Promise.all([
      process.exited,
      new Response(process.stdout).text(),
      new Response(process.stderr).text(),
    ])
    const diagnostic = diagnosticFrom(stdout.trim() || stderr.trim())
    if (!diagnostic) return

    return {
      content: [...event.content, { type: "text" as const, text: diagnostic }],
      isError: status !== 0,
    }
  })
}
