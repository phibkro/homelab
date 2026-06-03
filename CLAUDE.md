# Project guide for Claude (and other agents)

NixOS flake managing three machines:

- **workstation** — workhorse, NixOS x86_64. Caddy + Authelia + GPU/state-heavy services.
- **pi** — appliance, NixOS aarch64. Observability + alerting + DNS + tailnet plumbing that survives station outages.
- **macbook** — Intel Mac, standalone home-manager. Daily-driver laptop.

## Read in this order

| # | Doc | When to read |
|---|---|---|
| 1 | `docs/CONCEPTS.md` | Always-early — glossary + mental models. Without these, every other doc reads as undefined jargon |
| 2 | `docs/INVARIANTS.md` | Always-early — load-bearing claims tagged by enforcement tier. The drift register |
| 3 | `docs/PROCEDURES.md` | Skill index — which procedure-skill matches what intent |
| 4 | `docs/ROADMAP.md` | Forward plan: outstanding, deferred, backlog |
| 5 | `docs/TOPOLOGY.md` | Hosts, hardware, roles, GPU, resource caps |
| 6 | `docs/STORAGE.md` | btrfs, subvolumes, `nori.fs`, snapshot + backup policy |
| 7 | `docs/NETWORK.md` | Zones, `nori.lanRoutes`, audience model, Caddy + Authelia + DNS |
| 8 | `docs/SERVICES.md` | Service catalog + backup patterns A/B/C + observability |
| 9 | `docs/MODULES.md` | Module shape, service template, sops, packages-by-scope, dev workflow |
| 10 | `docs/ENFORCEMENT.md` | The enforcement ladder + how to add a rule |
| 11 | `docs/RECOVERY.md` | RTO targets, runbook index, permanent constraints |
| 12 | `docs/RATIONALES.md` | Hard-to-revisit design decisions (legacy list; newer go to `docs/decisions/`) |
| 13 | `docs/decisions/0001-agentic-homelab-practices.md` | The meta-ADR that sets the *why* behind everything |
| 14 | `.claude/skills/gotcha-*/` | Landmines as auto-loaded skills (35+). Each fires when its USE-WHEN trigger matches |
| 15 | `git log --oneline` | Commit-by-commit narrative for what the docs don't catch |

## Hard rules

- **Code is the single source of truth**; docs approximate.
- **Never touch `nvme0n1`** without verifying the model string via `/dev/disk/by-id/`. NVMe enumeration is unstable across reboots. Disko configs target by-id paths.
- **Don't commit secrets.** `secrets/secrets.yaml` is sops-encrypted and safe. `.env` files are gitignored. Public certs (e.g. `modules/server/caddy-local-ca.crt`) are fine.
- **Don't bypass the safety net.** Don't disable `services.restic.backups.*`, `services.btrbk.*`, OnFailure → ntfy alerts, or any other passive backend without naming why and how it'll be re-enabled.
- **Default-deny everywhere.** Network exposure, filesystem access, tailnet ports — services opt in to specific access, never wildcard.

## What's the bias

- **Correctness > simplicity > thoroughness > speed.**
- **Declarative over imperative.** When tools fight code-as-config, switch tools (we replaced Uptime Kuma with Gatus).
- **Composable abstractions, not god modules.** One input → multiple generators (`nori.lanRoutes` produces Caddy + DNS + Gatus + dashboard + Authelia client + sops template from one entry). The `nori.<X>` family follows the Reader + collected-Writer effect shape.
- **Rule of three for abstractions.** Extract only when three concrete uses exist. Two looks like a pattern; the third reveals the actual axis of variation.
- **Iterate-to-stable, then codify.** Novel patterns live in Cynefin's Complex domain — ship the simplest version, let the next constraint surface, codify after the shape stabilizes.
- **Workhorse-by-default, appliance-by-exception.** Services land on station unless they need to survive station's failure or are network appliance functions. The exception clause is "fate-sharing breaks the function," not "feels lightweight."
- **Tailnet IS the auth perimeter; Authelia only for per-user identity.** Encoded as the `audience` enum on `nori.lanRoutes` — `operator` trusts tailnet, `family` needs OIDC, `public` is intentionally open.
- **Comments explain WHY** (especially when the obvious approach didn't work).

## How to operate

- **Primary dev host: workstation** via Zed remote (Mac over SSH). Persistent clone at `~/Downloads/homelab`. Mac clone at `~/Documents/nix-migration`.
- Reach hosts:

  | Host | Tailnet | LAN |
  |---|---|---|
  | workstation | `workstation.saola-matrix.ts.net` · `100.81.5.122` | `192.168.1.181` |
  | pi | `pi.saola-matrix.ts.net` · `100.100.71.3` | `192.168.1.225` (static) |

  From Mac the `.ts.net` hostnames don't resolve through normal DNS — use LAN IPs for rsync/ssh. After Pi reboots its host key may regenerate; clear with `ssh-keygen -R <ip>` or `-o StrictHostKeyChecking=accept-new`.

- **Justfile is local-by-default**: `just rebuild` builds whichever host you're sitting on. From Mac (not a NixOS host): `just remote workstation rebuild` rsyncs to `/tmp/nix-migration/` + runs `just rebuild` there. Same pattern wraps any recipe.
- Push to `origin/main` is the deploy boundary; any host can `git pull && just rebuild` (or `just deploy` to build from origin).
- Long jobs go in the background — never block. Use `run_in_background: true`.

## Procedures

Recurring procedures live as skills under `.claude/skills/` so the body loads only when triggered. They auto-discover when the user's intent matches the trigger; manually invoke with `/<skill-name>`. The skill index lives in `docs/PROCEDURES.md`. The principle: **prose for facts (here + docs), skills for procedures (on demand)**; when a CLAUDE.md section grows into a procedure with non-deterministic branches, extract it.

## Quality gates

- `nix flake check` — standard Nix lints + repo-specific guard derivations (`every-service-has-fs-hardening`, `every-service-has-backup-intent`, `forbidden-patterns`, …). `nix flake show .#checks` for the live list.
- `nix fmt` — apply nixfmt.
- Pre-commit hook in `.githooks/pre-commit` runs `nix flake check` on staged `.nix` changes; enable once per clone with `git config core.hooksPath .githooks`. Skips gracefully if nix isn't on PATH (Mac); CI catches the skipped commits.
- Adding a new rule: see `docs/ENFORCEMENT.md` § decision tree.

## Style for prose

- No hedging in commits or docs. Lead with the answer, justify after.
- Match the existing tone — terse, technical, no fluff. The operator (Philip) reads fast and pushes back on weak decisions.
- Function-named subdomains, agnostic over branded: `status.nori.lan` not `gatus.nori.lan` unless the brand IS the identity.
