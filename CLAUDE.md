# Project guide for Claude (and other agents)

You are working in a NixOS homelab flake. Two-host topology (nori-station built; nori-pi deferred). Read these in order before making changes:

1. **`docs/DESIGN.md`** — canonical architecture. The "why" lives here. v2.x.
2. **`docs/CONVENTIONS.md`** — the established patterns for this repo. How modules are shaped, how secrets are wired, how new services are added.
3. **`docs/gotchas.md`** — landmines. Read before doing anything that touches: NVMe enumeration, Caddy CA trust, sops env files, openrsync flags, DynamicUser services.
4. **`docs/RESUME.md`** — current state, loose ends, where to pick up.
5. `git log --oneline` — commit-by-commit narrative for context the docs don't catch.

## Hard rules

- **Never touch `nvme0n1`** without verifying the model string first via `/dev/disk/by-id/`. NVMe enumeration is unstable across reboots — `nvme0n1` was the NixOS root at install time, is now Windows. Disko configs target by-id paths for this reason.
- **Don't commit secrets.** Anything in `secrets/secrets.yaml` is sops-encrypted and safe. `.env` files are gitignored. Public certs (e.g., `modules/services/caddy-local-ca.crt`) are fine to commit.
- **Don't bypass the safety net.** Don't disable `services.restic.backups.*`, `services.btrbk.*`, OnFailure → ntfy alerts, or any other "passive backend" without naming why and how it'll be re-enabled.
- **Default-deny everywhere.** Network exposure, filesystem access, tailnet ports — services opt in to specific access, never wildcard.

## How to add a new service

1. Create `modules/services/<service>.nix`
2. Enable the service module
3. Apply default-deny FS hardening (snippet in `docs/CONVENTIONS.md`)
4. Declare `nori.lanRoutes.<name> = { port = N; monitor = { }; };` for HTTPS access via Caddy + auto-monitoring
5. Add the import to `hosts/nori-station/default.nix`
6. If the service needs secrets: add to `secrets/secrets.yaml` via `sops secrets/secrets.yaml` (env-file format if env var bound)
7. If the service needs SSO: add an OIDC client to `modules/services/authelia.nix` + per-service env vars (see chat / metrics examples)
8. Sync working tree to host + `nixos-rebuild switch --flake .#nori-station`
9. Commit (Conventional Commits — type + scope + tight summary)

## How to operate

- Most work is from the Mac at `/Users/nori/Documents/nix-migration`. Push commits to `origin/main` (public GitHub repo).
- `ssh nori@192.168.1.181` to reach nori-station on the LAN. On tailnet: `nori-station.saola-matrix.ts.net` or `100.81.5.122`.
- For a rebuild: rsync the working tree to `/tmp/nix-migration/` on the host, then `nixos-rebuild switch --flake /tmp/nix-migration#nori-station`. Done from the Mac via SSH.
- Long jobs go in the background — never block on them. Use `run_in_background: true`.
- Background `Bash` and `Agent` invocations always (per the operator's CLAUDE.md global rule).

## What's the bias

- **Correctness > simplicity > thoroughness > speed** for code quality decisions.
- **Declarative over imperative.** If a service's config can live in Nix (sops-managed where secret), prefer that. When tools fight code-as-config, switch tools (we replaced Uptime Kuma with Gatus for this reason).
- **Composable abstractions, not god modules.** `modules/lib/lan-route.nix` is the model: one option, multiple generators (Caddy + Blocky + Gatus).
- **Code reviewers and future-you are the audience.** Comments explain *why* (especially when the obvious approach didn't work). Trace dependencies between modules in comments.

## Style for prose

- No hedging in commit messages or docs. Lead with the answer, justify after.
- Match the existing tone — terse, technical, no fluff. The operator (Philip) reads fast and pushes back on weak decisions.
- "Chat / ai / alert" naming convention: agnostic over branded. New services get function-named subdomains (`status.nori.lan` not `gatus.nori.lan`) unless the brand IS the identity.

## Quality gates

- `nix flake check` — eval validation + statix + deadnix + nixfmt format check
- `nix fmt` — apply nixfmt-rfc-style
- Pre-commit hook in `.githooks/pre-commit` runs `nix flake check` automatically
  when staged changes touch `.nix` files — enable once per clone with:
  `git config core.hooksPath .githooks`. Skips gracefully if nix isn't on PATH
  (Mac case); host validates on rebuild regardless. Bypass with
  `git commit --no-verify` for emergencies only.
