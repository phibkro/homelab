# Procedures

The non-deterministic recurring procedures — adding a service, adding a host, relocating a service to pi, wrapping up a session, refreshing docs after a structural change — live as skills under `.claude/skills/`, not as prose here. Skills load on demand (zero context cost when not invoked) and Claude auto-discovers them when the trigger phrasing matches.

| Intent | Skill | Trigger phrasing |
|---|---|---|
| Add a new self-hosted service | `/add-service` | "add <X>", "set up <Y>", "let's deploy <Z>" |
| Add a new NixOS host to the flake | `/add-host` | "add a new host", "set up nori-<X>", "another machine" |
| Migrate a service to pi | `/relocate-to-pi` | "move <X> to Pi", "<X> should survive station outages" |
| End-of-session wrap-up | `/wrap-session` | "wrap up", "ending session", "that's it for now" |
| Doc-tier decision after a structural change | `/on-structural-change` | "we just landed <X>", "what doc tier needs updating?" |

To invoke manually: `/skill-name`. To let Claude auto-discover: just describe the intent in natural language. Skill content (`.claude/skills/<name>/SKILL.md`) is the authoritative procedure; if you find yourself reasoning a procedure out from first principles, stop and let the skill expand.

For mechanical operations not large enough to warrant a skill (build, deploy, snapshot, restore-drill), see `just --list`.
