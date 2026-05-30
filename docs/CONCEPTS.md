---
summary: Glossary of the coined vocabulary — roles, the nori.<X> effect family,
  value tiers, audience, the split-module pattern, fate-sharing, dev-shell fragments.
---

# Concepts

The coined nouns and verbs this repo uses. One line per term, pointing at the
schema or source file that defines it. Read this to stop learning the vocabulary
by osmosis; read the source for the full shape.

| Term | Meaning | Source |
|---|---|---|
| **workhorse** | Host role: services land here by default — GPU, state-heavy, the HTTP entry plane. The `role` field on the host. | `modules/effects/hosts.nix` (`role`); set in `flake.nix` `identityFor` |
| **appliance** | Host role: only services that must survive the workhorse's failure (observability, alerting, DNS) or are network-appliance functions (subnet routing, exit node). Drives the placement assertion (appliance hosts can't use `paths`-based backups). | `modules/effects/hosts.nix`; assertion in `modules/effects/backup.nix` |
| **`nori.<X>`** | The repo's effect-interface family — one declarative input, many generated outputs. Reader + collected-Writer shape. | `modules/effects/`; CONVENTIONS.md "Effect interface — Reader + collected Writer" |
| **Reader (effect)** | `nori.<X>` flavor that hosts *produce* and services *read*: host-scoped context (`nori.hosts`, `nori.gpu`, `nori.fs`). Set in `flake.nix`/`hardware.nix`/`disko*.nix`. | `modules/effects/{hosts,gpu,fs}.nix` |
| **Writer (effect)** | `nori.<X>` flavor that services *contribute* and generators *interpret*: declarations assembled across modules (`nori.lanRoutes`, `nori.backups`, `nori.harden`). | `modules/effects/{lan-route,backup,harden}.nix` |
| **value tier** | Data-protection level driving snapshot/backup/retention: `re-derivable` (minimal) → `user`/`service` (daily + local) → `irreplaceable` (snapshots + local + off-site). | `modules/effects/fs.nix` (tier); DESIGN.md "Three value tiers" |
| **audience** | Per-route trust level: `operator` (trusts tailnet, no Authelia) / `family` (needs OIDC for per-user state) / `public` (intentionally open). Decides where Authelia layers on. | `modules/effects/lan-route.nix` (`audience`); CLAUDE.md bias section |
| **split-module pattern** | Cross-host service shipped as two modules: daemon module on the host that runs it, client/proxy module on every host. Live: `beszel`, `ntfy`. | `modules/server/{beszel,ntfy}/`; `/relocate-to-pi` skill |
| **fate-sharing** | The placement test: a service moves to the appliance only when "fate-sharing breaks the function" (it must outlive the workhorse), not because it "feels lightweight." | DESIGN.md "Pi as appliance"; CLAUDE.md "workhorse-by-default" bias |
| **`mkDevShell` / fragment** | Atomic dev-environment fragment (`modules/dev/<n>.nix`: a toolchain/runtime/tool); the composer resolves transitive deps, dedupes inputs, merges Claude allowlists. `nix eval .#lib.fragmentNames` lists them. | `modules/dev/default.nix` (composer); `modules/dev/*.nix` (fragments) |
