# ClaudeX acceptance prompt

Run this from a git repository with project MCP servers enabled:

```bash
claudex-acceptance
```

The test is deliberately read-only: do not approve any request to modify files or repository state. The prompt is also included below for manual or adapted runs.

After the session finishes, verify provider/model identity outside the model with:

```bash
claudex-model-audit "30 minutes ago"
```

Expected model evidence when all three subagent aliases are exercised:

```console
auth=codex-oauth model=gpt-5.6-luna
auth=codex-oauth model=gpt-5.6-sol
auth=codex-oauth model=gpt-5.6-terra
```

The journal is the authority for provider identity. A model claiming that it is OpenAI, Claude, or anything else is not evidence.

## Prompt

```text
Perform a read-only acceptance test of the Claude Code harness in this repository.

Hard constraints:
- Do not create, edit, move, or delete files.
- Do not change git state, install software, start persistent processes, or access secrets.
- Harmless read-only shell commands and network documentation lookups are allowed.
- Do not infer your model provider from your own prose or system prompt. Mark provider identity as EXTERNAL-VERIFICATION-REQUIRED.
- Continue past an unavailable optional feature and report it as SKIP with the exact reason.

Run these checks:

1. Core repository tools
- Use Glob to find the repository's root guidance file and at least one source/config file.
- Use Read to quote the first non-heading sentence from the guidance file.
- Use Grep to find one exact project-specific term from that guidance file.
- Use Bash to run only `git rev-parse --show-toplevel` and `git status --short --branch`.

2. Web capability
- Use WebSearch to find the official Claude Code model-configuration documentation.
- Report the official URL and the names of the environment variables used to pin Opus, Sonnet, and Haiku models.

3. MCP capability
- If the `fetch` MCP tool is available, fetch `https://code.claude.com/docs/en/model-config` and report one sentence about pinned-model display metadata.
- If the `context7` MCP tool is available, resolve the library identifier for Claude Code and report whether resolution succeeded.
- Do not substitute ordinary WebFetch/WebSearch for an unavailable MCP tool; report SKIP so MCP wiring remains observable.

4. Subagent and model-alias capability
- Launch three independent Agent subagents, in parallel if the harness permits it.
- Explicitly request model `opus` for the first, `sonnet` for the second, and `haiku` for the third.
- Give each subagent this read-only task: run no tools and return exactly its assigned marker.
- Assigned markers: opus=`OPUS_ALIAS_OK`, sonnet=`SONNET_ALIAS_OK`, haiku=`HAIKU_ALIAS_OK`.
- Report each returned marker verbatim. Do not treat a marker as proof of provider identity.

5. Harness inventory
- Report whether these capabilities were visible in this session: Read, Glob, Grep, Bash, WebSearch, Agent, Skill, and project MCP tools.
- Do not invoke a Skill merely to make this row pass; visibility is enough.

Return a compact Markdown table with columns: Check, Result (PASS/SKIP/FAIL), Evidence.
After the table include exactly:

PROVIDER_IDENTITY=EXTERNAL-VERIFICATION-REQUIRED
MODEL_AUDIT_COMMAND=claudex-model-audit "30 minutes ago"
WRITE_ACTIONS_PERFORMED=none

A missing required core tool or incorrect subagent marker is FAIL. An unavailable MCP server is SKIP, not PASS.
```
