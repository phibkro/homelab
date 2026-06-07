# Project guide for Claude (and other agents)

NixOS flake managing three machines:

- **workstation** — workhorse, NixOS x86_64. Caddy + Authelia + GPU/state-heavy services.
- **pi** — appliance, NixOS aarch64. Observability + alerting + DNS + tailnet plumbing that survives station outages.
- **macbook** — Intel Mac, standalone home-manager. Daily-driver laptop.

## Docs map

Filenames encode the topic. The `USE WHEN` column matches the skill/
memory convention — grep for the trigger phrase that fits your intent.
Sequencing matters only for early-orient docs (1-3); the rest is reached
on demand.

| # | Doc | USE WHEN |
|---|---|---|
| 1 | `docs/GLOSSARY.md` | first session in this repo, OR you hit jargon (`nori.<X>` effect family, audience, fate-sharing, split-module, value tiers) and need the canonical definition |
| 2 | `docs/INVARIANTS.md` | a claim sounds load-bearing and you want its enforcement rung, OR before writing prose that asserts "X is always Y" |
| 3 | `docs/SKILL_INDEX.md` | looking for a `/<skill-name>` that matches your current intent — recurring procedures live as skills, not prose |
| 4 | `docs/ROADMAP.md` | considering deferring work, checking what's queued, or wondering whether something is already planned |
| 5 | `docs/TOPOLOGY.md` | placing a service across hosts, sizing GPU/RAM caps, or reasoning about workhorse/appliance/agent roles |
| 6 | `docs/STORAGE.md` | touching btrfs subvolumes, `nori.fs.<X>`, snapshot/backup policy, or value-tier classifications |
| 7 | `docs/NETWORK.md` | adding a `nori.lanRoutes` entry, picking an audience, or working with Caddy + Authelia + DNS |
| 8 | `docs/SERVICES.md` | adding a service module, picking a backup pattern (A/B/C), or wiring observability for it |
| 9 | `docs/MODULE_AUTHORING.md` | writing a new module — the template, sops conventions, packages-by-scope, dev workflow |
| 9.5 | `docs/DOCUMENTATION_WRITING.md` | writing/auditing comments + prose — earns-rent taxonomy, anti-patterns, the agent-imitation loop |
| 10 | `docs/ENFORCEMENT.md` | promoting a claim from prose → comment → test → type, or deciding the right rung for a new rule |
| 11 | `docs/RECOVERY.md` | something is broken or you're planning recovery — RTO targets, runbook index, permanent constraints |
| 11.5 | `docs/RUNTIME_TESTS.md` | adding a `just test-<X>` lever or auditing whether an effect family ships with one |
| 12 | `docs/RATIONALES.md` | wondering "why was X chosen?" before re-litigating a design decision |
| 13 | `docs/decisions/0001-agentic-homelab-practices.md` | the meta-ADR that sets the *why* behind everything; read once, refer back when in doubt |
| 14 | `.claude/skills/gotcha-*/` | auto-load on trigger; manually `/<skill-name>` if it fits a known landmine |
| 15 | `git log --oneline` | a recent change isn't yet reflected in docs, or a comment references "2026-MM-DD incident" without enough context |

`docs/README.md` mirrors this table for agents that land in `docs/`
without CLAUDE.md context.

## Hard rules

- **Code is the single source of truth**; docs approximate.
- **Never touch `nvme0n1`** without verifying the model string via `/dev/disk/by-id/`. NVMe enumeration is unstable across reboots. Disko configs target by-id paths.
- **Don't commit secrets.** `secrets/secrets.yaml` is sops-encrypted and safe. `.env` files are gitignored. Public certs (e.g. `modules/services/caddy-local-ca.crt`) are fine.
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
- **Code describes behavior; comments encode intent.** See `docs/DOCUMENTATION_WRITING.md` — the earns-rent vs cut taxonomy + the amnesiac-imitation loop that makes seeding rent-paying examples load-bearing in an agent-driven codebase.

## How to operate

- **Primary dev host: workstation** via Zed remote (Mac over SSH). Persistent clone at `~/Downloads/homelab`. Mac clone at `~/Documents/nix-migration`.
- Reach hosts:

  | Host | Tailnet | LAN |
  |---|---|---|
  | workstation | `workstation.saola-matrix.ts.net` · `100.81.5.122` | `192.168.1.181` |
  | pi | `pi.saola-matrix.ts.net` · `100.100.71.3` | `192.168.1.225` (static) |

  From Mac the `.ts.net` hostnames don't resolve through normal DNS — use LAN IPs for rsync/ssh. After Pi reboots its host key may regenerate; clear with `ssh-keygen -R <ip>` or `-o StrictHostKeyChecking=accept-new`.

- **Justfile is local-by-default**: `just rebuild` builds whichever host you're sitting on. From Mac (not a NixOS host): `just remote workstation rebuild` rsyncs to `/tmp/nix-migration/` + runs `just rebuild` there. Same pattern wraps any recipe.
- **Iteration trio**: for non-load-bearing changes (themes, fonts, scalar tweaks) reach for `just option <path>` (inspect type + default + current + description, scoped to THIS flake's eval) → `just set <file> <attr> <value>` (AST splice via nix-editor + project nixfmt, preserves style) → `just preview` (`nh os test`, no boot entry; reboot reverts) → `just rebuild` (persist) or `git checkout` (revert). Closes the System-Prefs-style "try then commit" loop without inventing a settings UI.
- Push to `origin/main` is the deploy boundary; any host can `git pull && just rebuild` (or `just deploy` to build from origin).
- **Push gate (solo review).** Agents NEVER `git push` to `origin/main` without first running `git log -p origin/main..HEAD` (or `just pending`), surfacing the full diff inline, and getting explicit operator approval. Commit to `main` locally as before — only the push is gated. Worktrees are reserved for non-routine refactors where out-of-tree review pays off; routine work stays on `main`.
- Long jobs go in the background — never block. Use `run_in_background: true`.

## Procedures

Recurring procedures live as skills under `.claude/skills/` so the body loads only when triggered. They auto-discover when the user's intent matches the trigger; manually invoke with `/<skill-name>`. The skill index lives in `docs/SKILL_INDEX.md`. The principle: **prose for facts (here + docs), skills for procedures (on demand)**; when a CLAUDE.md section grows into a procedure with non-deterministic branches, extract it.

## Quality gates

- `nix flake check` — standard Nix lints + repo-specific guard derivations (`every-service-has-fs-hardening`, `every-service-has-backup-intent`, `forbidden-patterns`, …). `nix flake show .#checks` for the live list.
- `nix fmt` — apply nixfmt.
- Pre-commit hook in `.githooks/pre-commit` runs `nix flake check` on staged `.nix` changes; enable once per clone with `git config core.hooksPath .githooks`. Skips gracefully if nix isn't on PATH (Mac); CI catches the skipped commits.
- Adding a new rule: see `docs/ENFORCEMENT.md` § decision tree.

## Style for prose

- No hedging in commits or docs. Lead with the answer, justify after.
- Match the existing tone — terse, technical, no fluff. The operator (Philip) reads fast and pushes back on weak decisions.
- Function-named subdomains, agnostic over branded: `status.nori.lan` not `gatus.nori.lan` unless the brand IS the identity.
- Full rules for comments + docs (earns-rent taxonomy, hard rules on derived lists, anti-patterns) → `docs/DOCUMENTATION_WRITING.md`.
