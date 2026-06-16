# Project guide for Claude (and other agents)

NixOS flake managing four NixOS hosts + a home-manager macbook:

| Host | Role | Runs |
|---|---|---|
| **pi** | always-on appliance (aarch64) | HTTP entry plane (Caddy + Authelia + Blocky-authoritative), observability, alerting, Tailscale subnet+exit |
| **aurora** | always-on family vault (x86_64) | `/mnt/family/*` irreplaceable data, family-tier service backends (vaultwarden, immich, calibre-web, komga, navidrome, …), OneTouch restic target |
| **workstation** | sleep-friendly compute (x86_64) | Ollama, Jellyfin (NVENC), `*arr` stack + qBittorrent, `@downloads`, desktop. Cold replica of `/mnt/family/*` on MP510 |
| **pavilion** | agent quarantine (x86_64) | hermes worktrees, weekly tertiary `/mnt/family/*` replica (planned) |
| **macbook** | daily-driver laptop (intel x86_64) | standalone home-manager only — not under the flake's `nixosConfigurations` |

Three of the four NixOS hosts (pi, aurora, workstation) import the full `modules/services` bundle and opt into individual services via `nori.services.<X>.enable`. Importing the bundle gives a host the route registry; activation is per-service. See `docs/reference/module-authoring.md` for the convention.

## Docs map

All documentation lives under `docs/`. Read order is tier-encoded by
location: docs/ root for session-start essentials + roadmap,
`docs/reference/` for topic-triggered reference, `docs/<category>/`
for drill-down. Filenames encode the topic.

`docs/README.md` mirrors these tables for agents that land in `docs/`
without this file's context.

### Read on session start (mandatory)

| Doc | USE WHEN |
|---|---|
| `docs/glossary.md` | always, first — establishes vocabulary (`nori.<X>` effect family, audience, fate-sharing, value tiers, split-module). Every other doc reads as undefined jargon without it. |
| `docs/invariants.md` | always, second — load-bearing claims catalog + the enforcement ladder that keeps each true. Drift register (`[prose: unchecked]` = promotion candidate). Read before changing anything structural; also the doc to reach for when adding a new rule (§ "Decision tree — when to add a rule"). |

### Topic-triggered reference

| Doc | USE WHEN |
|---|---|
| `docs/roadmap.md` | considering deferring work, checking what's queued, or wondering whether something is already planned |
| `docs/reference/topology.md` | placing a service across hosts, sizing GPU/RAM caps, or reasoning about workhorse/appliance/agent roles |
| `docs/reference/storage.md` | touching btrfs subvolumes, `nori.fs.<X>`, snapshot/backup policy, or value-tier classifications |
| `docs/reference/network.md` | adding a `nori.lanRoutes` entry, picking an audience, or working with Caddy + Authelia + DNS |
| `docs/reference/services.md` | adding a service module, picking a backup pattern (A/B/C), or wiring observability |
| `docs/reference/module-authoring.md` | writing a new module — template, sops conventions, packages-by-scope, dev workflow |
| `docs/reference/documentation-writing.md` | writing/auditing comments + prose — earns-rent taxonomy, anti-patterns, agent-imitation loop |
| `docs/reference/recovery.md` | something is broken or you're planning recovery — RTO targets, runbook index, permanent constraints |
| `docs/reference/runtime-tests.md` | adding a `just test-<X>` lever or auditing whether an effect family ships with one |
| `docs/reference/capacity-baseline.md` | sizing a new service against current RAM/disk/CPU baselines per host |

### Drill-down (pulled in only when a parent doc cross-refs it)

| Path | USE WHEN |
|---|---|
| `docs/decisions/` | per-ADR for each hard-to-revisit choice. `0000-rationales.md` is the meta-index for smaller decisions; `0001-agentic-homelab-practices.md` is the philosophy meta-ADR |
| `docs/runbooks/` | per-incident recovery procedures (drive failure, USB enumeration, network split) |
| `docs/plans/` | multi-phase forward-looking work (aurora migration, docs deep-sweep, etc.) |
| `docs/specs/` | design specs preceding implementation |
| `docs/reports/` | after-action narratives — backward-looking companion to a plan in `docs/plans/` |
| `docs/installs/` | bring-up procedures (`baremetal.md`, `vm.md`) + `agent-onboarding-test.md` for validating a new agent's orientation |
| `.claude/skills/gotcha-*/` | auto-loaded on trigger; manually `/<skill-name>` if it fits a known landmine |
| `git log --oneline` | a recent change isn't yet reflected in docs, or a comment references "2026-MM-DD incident" without enough context |

## Hard rules

- **Code is the single source of truth**; docs approximate.
- **Never touch `nvme0n1`** without verifying the model string via `/dev/disk/by-id/`. NVMe enumeration is unstable across reboots. Disko configs target by-id paths.
- **Don't commit secrets.** `secrets/secrets.yaml` is sops-encrypted and safe. `.env` files are gitignored. Public certs (e.g. `services.openssh.knownHosts` entries) are fine.
- **Don't bypass the safety net.** Don't disable `services.restic.backups.*`, `services.btrbk.*`, OnFailure → ntfy alerts, or any other passive backend without naming why and how it'll be re-enabled.
- **Default-deny everywhere.** Network exposure, filesystem access, tailnet ports — services opt in to specific access, never wildcard.

## What's the bias

- **Correctness > simplicity > thoroughness > speed.**
- **Name the most-correct solution before any compromise.** Premature pragmatism assumes implicit constraints (dev cost, complexity, code volume) that often don't apply in an agentic workflow. State the right answer first, its real cost, what rules it out, then narrow. Each constraint the operator adds shrinks the solution space; re-research the most-correct within the narrowed space. Don't paint over the gap — when compromising, name the layer the policy *should* live at and what's given up to land where it does.
- **Declarative over imperative.** When tools fight code-as-config, switch tools (we replaced Uptime Kuma with Gatus).
- **Composable abstractions, not god modules.** One input → multiple generators (`nori.lanRoutes` produces Caddy + DNS + Gatus + dashboard + Authelia client + sops template from one entry). The `nori.<X>` family follows the Reader + collected-Writer effect shape.
- **Iterate-to-stable, then codify.** Novel patterns live in Cynefin's Complex domain — ship the simplest version, let the next constraint surface, codify after the shape stabilizes.
- **Workhorse-by-default, appliance-by-exception.** Services land on station unless they need to survive station's failure or are network appliance functions. The exception clause is "fate-sharing breaks the function," not "feels lightweight."
- **Tailnet IS the auth perimeter; Authelia only for per-user identity.** Encoded as the `audience` enum on `nori.lanRoutes` — `operator` trusts tailnet, `family` needs OIDC, `public` is intentionally open.
- **Code describes behavior; comments encode intent.** See `docs/reference/documentation-writing.md` — the earns-rent vs cut taxonomy + the amnesiac-imitation loop that makes seeding rent-paying examples load-bearing in an agent-driven codebase.

## How to operate

- **Primary dev host: workstation** via Zed remote (Mac over SSH). Persistent clone at `~/Downloads/homelab`. Mac clone at `~/Documents/nix-migration`.
- Reach hosts:

  | Host | Tailnet | LAN |
  |---|---|---|
  | workstation | `workstation.saola-matrix.ts.net` · `100.81.5.122` | `192.168.1.181` |
  | pi | `pi.saola-matrix.ts.net` · `100.100.71.3` | `192.168.1.225` (static) |

  From Mac the `.ts.net` hostnames don't resolve through normal DNS — use LAN IPs for rsync/ssh. After Pi reboots its host key may regenerate; clear with `ssh-keygen -R <ip>` or `-o StrictHostKeyChecking=accept-new`.

- **Justfile is local-by-default**: `just rebuild` builds whichever host you're sitting on. From Mac (not a NixOS host): `just remote workstation rebuild` rsyncs to `/tmp/nix-migration/` + runs `just rebuild` there. Same pattern wraps any recipe.
- **Iteration trio**: for non-load-bearing changes (themes, fonts, scalar tweaks) reach for `just show-option <path>` (inspect type + default + current + description, scoped to THIS flake's eval) → `just set <file> <attr> <value>` (AST splice via nix-editor + project nixfmt, preserves style) → `just preview` (`nh os test`, no boot entry; reboot reverts) → `just rebuild` (persist) or `git checkout` (revert). Closes the System-Prefs-style "try then commit" loop without inventing a settings UI.
- Push to `origin/main` is the deploy boundary; any host can `git pull && just rebuild` (or `just deploy` to build from origin).
- **Push gate (solo review).** Agents NEVER `git push` to `origin/main` without first running `git log -p origin/main..HEAD` (or `just show-pending-diff`), surfacing the full diff inline, and getting explicit operator approval. Commit to `main` locally as before — only the push is gated. Worktrees are reserved for non-routine refactors where out-of-tree review pays off; routine work stays on `main`.
- Long jobs go in the background — never block. Use `run_in_background: true`.

## Procedures

Recurring procedures live as skills under `.claude/skills/` so the body loads only when triggered. They auto-discover when the user's intent matches the trigger; manually invoke with `/<skill-name>`. The principle: **prose for facts (here + docs), skills for procedures (on demand)**; when a CLAUDE.md section grows into a procedure with non-deterministic branches, extract it.

## Quality gates

- `nix flake check` — standard Nix lints + repo-specific guard derivations (`every-service-has-fs-hardening`, `every-service-has-backup-intent`, `forbidden-patterns`, …). `nix flake show .#checks` for the live list.
- `nix fmt` — apply nixfmt.
- Pre-commit hook in `.githooks/pre-commit` runs `nix flake check` on staged `.nix` changes; enable once per clone with `git config core.hooksPath .githooks`. Skips gracefully if nix isn't on PATH (Mac); CI catches the skipped commits.
- Adding a new rule: see `docs/invariants.md` § decision tree.

## Style for prose

- No hedging in commits or docs. Lead with the answer, justify after.
- Match the existing tone — terse, technical, no fluff. The operator (Philip) reads fast and pushes back on weak decisions.
- Function-named subdomains, agnostic over branded: `status.nori.lan` not `gatus.nori.lan` unless the brand IS the identity.
- Full rules for comments + docs (earns-rent taxonomy, hard rules on derived lists, anti-patterns) → `docs/reference/documentation-writing.md`.
