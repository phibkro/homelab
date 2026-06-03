---
summary: Glossary of the coined vocabulary AND the mental models — roles,
  `nori.<X>` effect family, value tiers, audience, split-module, fate-sharing,
  dev-shell fragments, plus the practices that justify everything (rule of three,
  iterate-to-stable, declarative-over-imperative, composable abstractions,
  tailnet-as-perimeter, agentic-homelab asymmetries).
---

# Concepts

The coined nouns/verbs this repo uses, plus the mental models that justify them.
One line per term, pointing at the source-of-truth doc. Read this to stop
learning the vocabulary by osmosis; read the linked source for the full shape.

## Glossary — coined nouns + verbs

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

## Mental models — the practices that justify the abstractions

| Model | What it says | Source |
|---|---|---|
| **rule of three** | Don't extract an abstraction until three concrete uses exist. Two looks like a pattern; the third reveals the actual axis of variation. Premature abstraction locks in conventions before the variation is understood. | CLAUDE.md "What's the bias" |
| **iterate-to-stable, then codify** | Novel patterns live in Cynefin's Complex domain — the right shape isn't visible upfront. Ship the simplest version that works, let the next constraint surface, iterate. Codify (as a How-to / abstraction / convention) only after the shape stabilizes through use. | CLAUDE.md "What's the bias"; ADR-0001 |
| **declarative over imperative** | Configuration goes in Nix (or the abstraction layer) rather than scripts. When tools fight code-as-config, switch tools — replaced Uptime Kuma with Gatus for this reason. | CLAUDE.md "What's the bias" |
| **composable abstractions, not god modules** | One declarative input, multiple generators interpreting it (the `nori.<X>` family shape). Anti-pattern: god modules that span concerns. The canonical example is `modules/effects/lan-route.nix` — one entry produces Caddy + DNS + Gatus + dashboard + Authelia client + sops template. | CLAUDE.md "What's the bias"; `modules/effects/lan-route.nix` |
| **tailnet-as-auth-perimeter** | Device-level trust from Tailscale IS the perimeter; Authelia only layers on where the app needs per-user state. Encoded as the `audience` field of `nori.lanRoutes` — operator routes trust tailnet, family routes need OIDC, public is intentionally open. | CLAUDE.md "What's the bias"; `audience` row above |
| **agentic homelab asymmetries** | Three asymmetries vs human teams justify this repo's docs-heavy / skills-for-procedures / flake-checks-as-evidence shape: (1) bus factor = 1 per session, (2) context not time is the scarce resource, (3) agents confabulate so claims need verification. Drops practices that don't address them (feature branches, code review as gate, onboarding meetings). | ADR-0001 |
| **prose → comment → test → CI rule** | The enforcement ladder. Every load-bearing claim is on some rung; the goal is push toward stronger enforcement where the toolchain supports it. `[prose: unchecked]` entries in INVARIANTS.md are the promotion candidates. | `docs/INVARIANTS.md`; `docs/CONVENTIONS.md` "Enforcing conventions through code" |
