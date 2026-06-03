---
summary: The skill index — which recurring-procedure skill handles what intent, and
  how to add a new skill. Skills live in .claude/skills/ and load on demand.
---

# Procedures

The non-deterministic recurring procedures — analysing the system, adding a service, adding a host, relocating a service to pi, wrapping up a session, refreshing docs after a structural change — live as skills under `.claude/skills/`, not as prose here. Skills load on demand (zero context cost when not invoked) and Claude auto-discovers them when the trigger phrasing matches.

| Intent | Skill | Trigger phrasing |
|---|---|---|
| Fresh-session structural read | `/analyse-system` | "explore the codebase", "analyse the system", "orient yourself", "get up to speed" |
| Add a new self-hosted service | `/add-service` | "add <X>", "set up <Y>", "let's deploy <Z>" |
| Add a new NixOS host to the flake | `/add-host` | "add a new host", "set up nori-<X>", "another machine" |
| Migrate a service to pi | `/relocate-to-pi` | "move <X> to Pi", "<X> should survive station outages" |
| End-of-session wrap-up | `/wrap-session` | "wrap up", "ending session", "that's it for now" |
| Doc-tier decision after a structural change | `/on-structural-change` | "we just landed <X>", "what doc tier needs updating?" |

To invoke manually: `/skill-name`. To let Claude auto-discover: just describe the intent in natural language. Skill content (`.claude/skills/<name>/SKILL.md`) is the authoritative procedure; if you find yourself reasoning a procedure out from first principles, stop and let the skill expand.

### When each fires

| Skill | When |
|---|---|
| `/analyse-system` | Fresh session start — orientation pass |
| `/add-service`, `/add-host`, `/relocate-to-pi` | At the moment of doing that work |
| `/add-oidc-client` | At the moment of bootstrapping a new SSO client |
| `/on-structural-change` | **Immediately after a structural change lands** — not at session end. Drift compounds; the cost of an immediate doc refresh is small, the cost of a fresh agent acting on stale info is large. |
| `/wrap-session` | **At session end** — pushes pending commits, refreshes orientation docs, updates memory, writes the handoff. Per-change updates should already have happened via `/on-structural-change`. |

Both `/on-structural-change` and `/wrap-session` fire during a session that included structural changes — the first per-change as a small immediate fix, the second once at the end as the broader compactor + handoff.

For mechanical operations not large enough to warrant a skill (build, deploy, snapshot, restore-drill), see `just --list`.

## Adding a skill

`mkdir .claude/skills/<n> && $EDITOR .claude/skills/<n>/SKILL.md`. Frontmatter requires `description` (drives auto-discovery — put the key use case first). See https://code.claude.com/docs/en/skills for the canonical format; existing skills are good templates.

The principle: prose for facts (always-loaded in CLAUDE.md), skills for procedures (load on demand, zero always-loaded cost). When a CLAUDE.md section grows into a procedure with non-deterministic branches, extract it.
