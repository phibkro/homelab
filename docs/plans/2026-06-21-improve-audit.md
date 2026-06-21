---
summary: "/improve audit of the homelab on 2026-06-21. Three parallel Explore agents covered architecture, security+correctness, and tests+direction; this file consolidates vetted findings, lists what was rejected and why, and proposes a plan ordering. The operator chooses which findings to turn into individual implementation plans."
status: AUDIT — awaiting plan selection
audited_at: 2026-06-21
audited_commit: 125a07f
audit_method: /improve skill (shadcn-improve v1.0.0) with 3 Explore subagents
---

# /improve audit — 2026-06-21

## Method

- **Recon**: read `CLAUDE.md`, `docs/glossary.md`, `docs/invariants.md`, `docs/roadmap.md`, `flake.nix` (1032 lines), `modules/` structure, recent commit history (`git log -15`).
- **Audit**: 3 parallel Explore subagents — (a) architecture/tech-debt, (b) security+correctness, (c) tests+direction. Each given the audit playbook + recon facts + Hard Rules 4 & 6 + already-decided tradeoffs to suppress.
- **Vet**: each finding's cited code was re-read directly here; subagent attributions corrected; duplicates collapsed; by-design behavior moved to "rejected" with rationale.

## Vetted findings — ranked by leverage

Leverage = (impact ÷ effort) weighted by confidence. Risk filters out low-confidence picks.

| # | Finding | Category | Impact | Effort | Risk | Confidence | Notes |
|---|---|---|---|---|---|---|---|
| **1** | `test-harden` runtime introspection recipe missing | Test coverage | HIGH | S–M | LOW | HIGH | `nori.harden.<svc>` is declared by every service module; no recipe queries `systemctl show` to verify the hardening actually landed. Sibling pattern: `test-backups`, `test-routes`. |
| **2** | `test-fs` runtime introspection recipe missing | Test coverage | HIGH | S | LOW | HIGH | `nori.fs.<n>` path/owner/subvolume drift is silent until restore. Scored 4-lever `leverage 3 · volatility 1 · opacity 3 · blast 4` per `docs/reference/runtime-tests.md`. |
| **3** | `infra-concerns-have-tests` meta-check not mechanized | Test coverage | HIGH | M | LOW | HIGH | Already on `docs/roadmap.md § Promotion register`. Prevents future regressions like #1 + #2: any new `modules/infra/<X>/default.nix` with Reader+Writer shape must ship `test-<X>`. |
| **4** | `systemd-execstart-resolves` flake check not implemented | Test coverage | HIGH | M | MED | HIGH | Already on roadmap. Incident 2026-06-03 class (restart-loop bombs from bad ExecStart). Eval-time introspection over `config.systemd.services.*.serviceConfig.ExecStart`. |
| **5** | `audience` enum is informational, not enforced | Security | MED | S–M | LOW | HIGH | `audience=family` without an `oidc` or `forwardAuth` block currently lands silently. Schema docstring at `modules/infra/networking/default.nix:354` itself flags this as a TODO ("future flake checks may assert consistency"). |
| **6** | `test-all` composite excludes `test-eval` | DX | LOW | XS | LOW | HIGH | `Justfile:181-188` lists 6 test recipes; `test-eval` (line 660) exists but isn't called. Local `just test-all` green ≠ CI green for eval drift. One-line fix. |
| **7** | Generated docs only cover 3 of N `nori.<X>` schemas | Docs | MED | M-per-schema | LOW | MED | `docs-fresh` check covers `nori.lanRoutes`, `nori.hosts`, `nori.harden+gpu`. Missing: `nori.backups`, `nori.fs`, `nori.replicas`. Hand-written `docs/reference/*` approximates but diverges silently. |
| **8** | Layer-2 nixosTest gap on stateful family services | Test coverage | MED | L | MED | MED | Immich (2 units + ML sync + sops), Navidrome (pattern-C2 race history), Vaultwarden (DB migration on boot) lack dedicated `tests/e2e-*` coverage. Family-tier visibility if broken. |
| **9** | `flake.nix` is 1032 lines | Tech debt | MED | M (extract) → L (dendritic refactor) | LOW | HIGH | **Superseded by operator's dendritic-pattern question.** Half-measure: extract `mkNixdocSection`/`mkFileDocstring` to `lib/docs.nix` (saves ~150 lines). Full-measure: dendritic via `flake-parts` (saves ~900 lines, all checks/packages become per-file). See § "Dendritic decision" below. |

## Rejected (with rationale)

Recorded so they don't get re-audited next run. Cite this file in the next `/improve` pass to skip these.

| Subagent claim | Rejection rationale |
|---|---|
| qBittorrent TempPath not in `nori.harden.qbittorrent.binds` | Hypothetical bug — `modules/infra/capabilities/default.nix:125` explicitly states `ProtectSystem=strict` is deliberately NOT applied. The "latent if hardening tightens" framing assumes a future config change that's been explicitly rejected. |
| filmder-build fetches GitHub source without integrity verification | The repo is operator-owned (`github.com/phibkro/filmder`). Threat model is "operator's GitHub credentials are compromised" — much further perimeter than typical supply-chain. Existing operator-discipline mitigation is appropriate. |
| hermes dashboard `--insecure` flag | By-design — `modules/services/hermes.nix:31-42` documents the Host+Origin rewrite defense; operator-only behind tailnet perimeter. `PrivateNetwork=true` would break the dashboard. |
| filmder/heim `audience=public` lacks documented threat model | Already documented — `modules/services/filmder.nix:52-55` clarifies `public` = tailnet-public, not internet-public. Real gap is the *schema*-level doc (see finding #5). |
| `samba.nix` exemption from `every-service-has-fs-hardening` | Already explicit — `flake.nix:883` comments call it out as "legitimate /srv-full-access exception". Adding a `nori.harden.samba = { protectHome = false; }` no-op declaration would be a wart, not a fix. |
| Media group declared in 3 places (arr/shared, immich, aurora) | Already acknowledged — `modules/infra/capabilities/default.nix:17` comment names this with explicit deferral. Group membership is idempotent; current cost ≤ refactor cost. |
| Radicale htpasswd setup is imperative | Operator one-shot at bootstrap, not activation-time. No real risk; relocating to a runbook is style preference, not a finding. |
| `access` infra concern lacks `options.nori.*` Reader schema | Verified: `modules/infra/access/default.nix` is a 24-line import aggregator. Adding a Reader schema for a 24-line module is premature abstraction (violates rule-of-three). |
| `observability` infra concern lacks `options.nori.*` Reader schema | Partial-truth — observability *consumes* `nori.lanRoutes` to emit Gatus probes (one input → multiple generators IS the Reader+Writer shape, just on a borrowed registry). Promoting it to its own `options.nori.observability` is plausible but no current pain. |

## Direction items (separate from findings)

These are forward-looking suggestions; weigh them as options, not problems.

### D-A — Complete the promotion register

`docs/invariants.md § promotion work-list` names two `[prose: unchecked]` items as ready to mechanize:

1. `systemd-execstart-resolves` → covered by finding #4 above
2. `workhorse-vs-appliance-placement` → not in this audit's findings; per-service role-vs-host assertion at eval time

Bundling these as a single "promotion register completion" plan is natural: each addition is small, the pattern (eval-time check derivation) is established (`every-service-has-fs-hardening` is the exemplar). Net result: three convictions move from prose → law.

### D-B — Layer-2 nixosTest expansion for stateful services

Finding #8 expanded. Suggested order: **immich** first (two units + ML sync + sops + family-tier — high learning value), then vaultwarden (DB migration), then navidrome (pattern-C2 race regression test). Each ~150-300 lines testScript following `tests/e2e-pi-smoke.nix` as template.

### D-C — Dendritic refactor (operator-initiated)

The dendritic pattern (single flake, decomposed via `flake-parts` modules) cleanly solves finding #9 and makes findings #3/#4/#7 cheaper to implement (each is one new file, not a diff against the 1032-line flake.nix). Costs: ~1-2 day refactor, adds `flake-parts` as foundational input, learning curve for new contributors.

**Decision gate** (operator):
- "I avoid editing `flake.nix` because it's annoying" → do dendritic next, bundle with #3/#4 implementation.
- "It's long but not painful" → land half-measure (extract `lib/docs.nix`), defer dendritic to next inflection point.

If chosen, propose dedicated `paths/PATH-dendritic-refactor.md` per the project's PATH convention. Phases: input + thin shim → migrate one check (proof of pattern) → migrate the rest in batches → CI green at every phase → diff inline review per push-gate.

### D-D — Onboarding clarity (Mac activation)

The Mac `home-manager switch` command lives in `docs/roadmap.md § Deferred § Mac is on x86_64-darwin EOL clock` table. Reachable but not where an operator looks first. `test-agent-onboarding` recipe exists at `Justfile:796` — verify it asks about Mac activation; if so, missing answer is the gap; if not, recipe needs the question added. Cost: 1-line CLAUDE.md addition + possible Justfile recipe update.

## Suggested plan-write order

Roughly highest-leverage first; #1+#2+#3 chain naturally (mechanize the meta-check AFTER writing the two example recipes it'll enforce):

1. **Bundle "infra concern test coverage"** — findings #1, #2, #3 as one PATH. Land `test-harden` and `test-fs` recipes first; then implement the `infra-concerns-have-tests` flake check; the two new recipes prove the convention before the check enforces it.
2. **finding #5** — `audience` enum enforcement. Standalone, S effort, M impact. Quick win.
3. **finding #6** — `test-all` includes `test-eval`. One-line patch + retest.
4. **finding #4** — `systemd-execstart-resolves` check. Standalone, M effort, real incident-class fix.
5. **finding #7** — extend `docs-fresh` to cover `nori.backups`/`nori.fs`/`nori.replicas`. One generator + one check per schema; can be three separate small plans or one bundled.
6. **finding #8** — layer-2 nixosTest for immich (template), then vaultwarden + navidrome. Heavy; consider only if recent regressions justify.
7. **finding #9** — dendritic refactor. Operator-gated per D-C.

## Awaiting operator selection

Pick which findings to turn into individual implementation plans (default suggestion: #1-bundle + #5 + #6 + #4 — the top 4 by leverage). Each selected plan gets its own file at `docs/plans/2026-06-21-<slug>.md` following the project's existing plan-file convention.

If non-interactive, default = #1-bundle + #5 + #6.
