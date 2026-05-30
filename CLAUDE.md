# Project guide for Claude (and other agents)

You are working in a NixOS homelab flake managing three machines:

- **workstation** — workhorse, NixOS host. Bare metal x86_64 (Ryzen 5600X + RTX 5060 Ti). Runs Caddy, Authelia, all GPU/media/state-heavy services (Ollama, Jellyfin, Immich, *arr stack, Vaultwarden, etc.).
- **pi** — appliance, NixOS host. Raspberry Pi 4, aarch64. Runs the observability + alerting + DNS plane that needs to survive station outages: Beszel hub, ntfy server, Gatus, Blocky in forwarder mode, Tailscale subnet router + exit node.
- **macbook** — Intel Mac, x86_64-darwin (not a NixOS host; standalone home-manager only). Daily-driver laptop; Nix-managed CLI baseline + interactive operator tools, brew for Mac-only / Darwin-missing packages (utm, ghostty, tailscale).

Per-machine layout: `machines/<n>/` holds everything for one machine. NixOS hosts get `default.nix` + `hardware.nix` + `disko*.nix` + `home.nix`; non-NixOS machines (Mac) get only `home.nix`. Cross-machine user baseline lives at `machines/core.nix`. All `home.nix` files are pure home-manager modules; the home-manager-as-NixOS-module wrapping happens once inside each NixOS machine's `default.nix`. See `docs/CONVENTIONS.md` § Module structure for the full shape.

Read these before making changes:

1. **`docs/DESIGN.md`** — canonical architecture + current-state reference. The "why" lives here. v2.x.
2. **`docs/ROADMAP.md`** — the forward plan: outstanding work, deferred items, idea backlog. The "what's next" (single home; `git log` is the shipped history).
3. **`docs/CONCEPTS.md`** — glossary of the coined vocabulary (roles, the `nori.<X>` effect family, value tiers, audience, split-module, fate-sharing, dev-shell fragments). Read when a term is unfamiliar.
4. **`docs/CONVENTIONS.md`** — established patterns. How modules are shaped, secrets are wired, services are added.
5. **`docs/gotchas.md`** — landmines. Read before touching: NVMe enumeration, Caddy CA trust, sops env files, openrsync flags, DynamicUser services.
6. **`.claude/skills/`** — recurring procedures (add a service, add a host, relocate to Pi, wrap session, on structural change). Auto-discovered when the trigger phrasing matches; load on demand. `docs/PROCEDURES.md` is the index.
7. `git log --oneline` — commit-by-commit narrative for context the docs don't catch.

## Hard rules

- **Code is the single-source-of-truth**, documentation is merely an approximation.
- **Never touch `nvme0n1`** without verifying the model string first via `/dev/disk/by-id/`. NVMe enumeration is unstable across reboots — `nvme0n1` was the NixOS root at install time, is now Windows. Disko configs target by-id paths for this reason.
- **Don't commit secrets.** Anything in `secrets/secrets.yaml` is sops-encrypted and safe. `.env` files are gitignored. Public certs (e.g., `modules/server/caddy-local-ca.crt`) are fine to commit.
- **Don't bypass the safety net.** Don't disable `services.restic.backups.*`, `services.btrbk.*`, OnFailure → ntfy alerts, or any other passive backend without naming why and how it'll be re-enabled.
- **Default-deny everywhere.** Network exposure, filesystem access, tailnet ports — services opt in to specific access, never wildcard.

## Procedures

Recurring procedures live as skills under `.claude/skills/` so the body loads only when the trigger fires (zero always-loaded cost). They auto-discover when the user's intent matches the trigger description; manually invoke with `/<skill-name>`. The skill index (which skill, what triggers it) and how to add one live in **`docs/PROCEDURES.md`** — the single home. If you find yourself reasoning a procedure out from first principles, stop and let the skill expand. The principle: prose for facts (always-loaded here), skills for procedures (load on demand); when a CLAUDE.md section grows into a procedure with non-deterministic branches, extract it.

## How to operate

- **Primary dev host: workstation** via Zed remote (Mac connects over SSH). Persistent clone at `~/Downloads/homelab` on the host. `~/Documents/nix-migration` on Mac is the laptop-side clone.
- Reach workstation: `ssh workstation` (alias if configured), `ssh nori@workstation.saola-matrix.ts.net` (tailnet hostname), `ssh nori@100.81.5.122` (tailnet IP), or `ssh nori@192.168.1.181` (LAN).
- Reach pi: `ssh nori@pi.saola-matrix.ts.net` (tailnet hostname), `ssh nori@100.100.71.3` (tailnet IP), or `ssh nori@192.168.1.225` (LAN — static lease).
- **From Mac** the tailnet `.ts.net` hostnames don't resolve through normal DNS — use LAN IPs (`192.168.1.181` station, `192.168.1.225` Pi) for rsync/ssh. After Pi reboots its host key may regenerate; clear stale entries with `ssh-keygen -R <ip>` or pass `-o StrictHostKeyChecking=accept-new`. From a tailnet-attached host (i.e. Zed-remoted into station) the magicDNS hostnames work normally.
- Push from workstation via SSH (`git@github.com:phibkro/homelab.git`). Mac uses HTTPS (default).
- **Justfile is local-by-default**: `just rebuild` builds whichever host you're sitting on (`nh os switch . -H $(hostname)`). From Mac — which isn't a NixOS host — recipes don't make sense locally; use the `remote` composition primitive instead: `just remote workstation rebuild` rsyncs the working tree to `/tmp/nix-migration/` on workstation + runs `just rebuild` there. Same pattern wraps any recipe: `just remote workstation status`, `just remote workstation logs sshd`, etc. Note: `just remote` uses the tailnet hostname; from Mac it may need replacing with direct rsync+ssh by LAN IP.
- Push to `origin/main` is the deploy boundary; any host can `git pull && just rebuild` (or `just deploy` to build from origin without touching the working tree).
- Long jobs go in the background — never block on them. Use `run_in_background: true`.
- Background `Bash` and `Agent` invocations always (per the operator's CLAUDE.md global rule).

## Current state

The durable architecture reference — topology + service placement, the topology
registry, hardware, GPU/memory/resource caps, the `nori.fs`/`nori.backups`/OIDC/
dashboard abstractions, dev-shell composer, Stylix, self-deployed apps — lives in
**`docs/DESIGN.md`** (canonical architecture + current-state reference). Read it
before touching any of those areas.

## Outstanding

The forward plan — actionable work, deferred items, idea backlog — lives in
**`docs/ROADMAP.md`** (the single home; routine done-work lives in `git log`).

## What's the bias

- **Correctness > simplicity > thoroughness > speed** for code quality decisions.
- **Declarative over imperative.** If a service's config can live in Nix (sops-managed where secret), prefer that. When tools fight code-as-config, switch tools (we replaced Uptime Kuma with Gatus for this reason).
- **Composable abstractions, not god modules.** `modules/effects/lan-route.nix` is the canonical example: one declarative option, multiple generators (Caddy vhost + Blocky DNS + Gatus monitor + Authelia client + Glance dashboard + sops template). The `nori.<...>` family in `modules/effects/` follows the same one-input-many-outputs shape — collectively a Reader + collected-Writer effect interface (hosts produce host-scoped context, services contribute declarations, generators interpret). See `docs/CONVENTIONS.md` "Effect interface — Reader + collected Writer".
- **Rule of three for abstractions.** Extract a function / module / macro only when three concrete uses exist. Two instances look like a pattern but are often coincidence; the third reveals the actual axis of variation. Premature abstraction locks in conventions before the variation is understood. Currently pending: cross-host service split has 2 instances (beszel hub, ntfy server) — wait for the 3rd before extracting `mkCrossHostService`.
- **Iterate-to-stable, then codify.** Novel patterns live in Cynefin's Complex domain — the right shape isn't visible upfront. Ship the simplest version that works, let the next constraint surface, iterate. Codify (as a "How to" / abstraction / convention) only after the shape stabilizes through use. The host registry was built three times in one session before stabilizing on `readDir` + `genAttrs` + `identityFor` — premature commitment to any of the earlier shapes would have been thrown away.
- **Workhorse-by-default, appliance-by-exception.** Services land on station unless they need to survive station's failure (observability, alerting, DNS) or are part of the network appliance role (subnet routing, exit node). Pi has 8 GiB and anti-write storage — every additional service competes with the observer role. The exception clause is "fate-sharing breaks the function," not "feels lightweight."
- **Tailnet IS the auth perimeter; layer Authelia only where per-user identity matters.** All access is tailnet-mediated, so device-level trust is already established before any HTTP request lands. Layering Authelia on top of operator-only services duplicates the network-perimeter guarantee for no gain while making Authelia uptime load-bearing for operator workflows. Encoded as `nori.lanRoutes.<n>.audience` (operator | family | public): operator routes trust tailnet; family routes need OIDC for per-user state propagation into the app (Jellyfin watch progress, Immich photo libraries, Vaultwarden vaults); public routes (home/Glance, status/Gatus, auth/Authelia) are intentionally open. Forward-auth survives only where the app is family-facing AND lacks native OIDC (Komga, calibre-web).
- **Code reviewers and future-you are the audience.** Comments explain *why* (especially when the obvious approach didn't work). Trace dependencies between modules in comments.

## Leverage map

The dated Meadows-leverage-tier snapshot (where the lab sits at each tier, across artifact / dev-workflow / agentic-workflow) lives in **`docs/DESIGN.md`** § "Leverage map". Use `/analyse-system` at session start to refresh it against current code; drift is expected.

## Style for prose

- No hedging in commit messages or docs. Lead with the answer, justify after.
- Match the existing tone — terse, technical, no fluff. The operator (Philip) reads fast and pushes back on weak decisions.
- "Chat / ai / alert" naming convention: agnostic over branded. New services get function-named subdomains (`status.nori.lan` not `gatus.nori.lan`) unless the brand IS the identity.

## Quality gates

- `nix flake check` — standard Nix lints (statix, deadnix, format) plus the repo-specific guard derivations declared in `flake.nix` `checks.${system}`. Categories: eval-time module assertions, `every-service-has-<X>` pattern enforcement, `forbidden-patterns` anti-pattern grep. Run `nix flake show .#checks` for the live list.
- `nix fmt` — apply nixfmt.
- Pre-commit hook in `.githooks/pre-commit` runs `nix flake check` automatically when staged changes touch `.nix` files — enable once per clone with `git config core.hooksPath .githooks`. Skips gracefully if nix isn't on PATH (Mac case); GitHub Actions (`.github/workflows/check.yml`) catches the skipped commits on push. Bypass with `git commit --no-verify` for emergencies only.
- Conventions for new rules (when to encode as types vs assertions vs flake checks vs leave to review): `docs/CONVENTIONS.md` § "Enforcing conventions through code".

