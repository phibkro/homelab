# Bank landing review map

Review boundary for the accepted-as-landed range `2d0e086..bd89038`.
Nothing in this range is deployment-approved; deployment remains gated on an
operator rebuild after reviewing the axes below.

The landed history is not identical to the five preserved extraction refs.
`2c2a9d7` mixed intended `docs/PROJECTS.md` work with 29 staged bank paths;
the networking, services, and documentation extraction commits then landed
linearly. The home and corrected-test commits remain only on local review refs.
That distinction is explicit below so review does not infer behavior from a ref
that is absent from `main`.

## Home / operator tooling

- **Review ref:** `pr/bank-home-desktop` (`4c1daa9`)
- **Landed range:** `2d0e086..2c2a9d7` (home paths selected from the mixed commit)
- **Preserved-only range:** `2c2a9d7..4c1daa9` — **not landed**
- **Risk class:** **network-exposure** — the landed JUCI procedure can inspect and
  mutate router policy, including WAN forwarding.

**Landed files:**

- `modules/home/agent-skills/default.nix`
- `modules/home/agent-skills/manage-genexis-juci/SKILL.md`
- `modules/home/agent-skills/manage-genexis-juci/agents/openai.yaml`
- `modules/home/agent-skills/manage-genexis-juci/references/api.md`
- `modules/home/agent-skills/manage-genexis-juci/references/inspect-firewall.example.json`
- `modules/home/agent-skills/manage-genexis-juci/references/port-forward-https.template.json`
- `modules/home/agent-skills/manage-genexis-juci/references/procedure-policy.md`
- `modules/home/agent-skills/manage-genexis-juci/scripts/juci_procedure.py`
- `modules/home/agent-skills/manage-genexis-juci/scripts/test_juci_procedure.py`

**Preserved ref adds, but main does not contain:**

- `.gitignore`
- `modules/home/agent-skills/default.nix` (current-profile commentary correction)
- `modules/home/claude-code/CLAUDE.md`
- `modules/home/claude-code/default.nix`
- `modules/home/profiles/desktop/communication.nix`
- `modules/home/profiles/development/agentic-tools.nix`

The landed portion adds one provider-neutral Genexis/JUCI skill, its guarded
procedure implementation, references, templates, and Python tests. It does not
wire that module into the current `agentic-tools` profile, add the required
ignore rules, install the Linux Tidal client, or carry the Claude pin/policy
updates; those corrections exist only on the preserved ref. Review the skill as
privileged network tooling even though no NixOS service is activated by the
landed portion.

## Networking / entry plane

- **Review ref:** `pr/bank-network-observability` (`e949223`)
- **Landed range:** `2c2a9d7..e949223`
- **Risk class:** **network-exposure**

**Files:**

- `lint/rules.toml`
- `modules/infra/networking/caddy/runtime.nix`
- `modules/infra/networking/cloudflare-ddns/manifest.nix`
- `modules/infra/networking/cloudflare-ddns/runtime.nix`
- `modules/infra/networking/default.nix`

This axis introduces the `internal`/`internet` route boundary, lowers internal
routes to Caddy private/tailnet client-IP matchers, rejects unknown or
network-ineligible hosts with a final 404, and forbids operator routes from
becoming internet-reachable. It also adds a Cloudflare DDNS adapter whose exact
DNS-only IPv4 records derive from the same route registry. This is the highest
risk axis: a matcher, source-address, cleanup, or ownership-selector mistake can
expose internal services or mutate the wrong DNS record.

## Family media services

- **Review ref:** `pr/bank-services` (`e61cee8`)
- **Landed range:** `e949223..e61cee8` (`70398f9`, `e61cee8`)
- **Risk class:** **services**

**Files:**

- `inventory/profiles.nix`
- `inventory/workloads.nix`
- `modules/services/arr/jellyseerr.nix`
- `modules/services/arr/manifests/jellyseerr.nix`
- `modules/services/jellyfin/manifest.nix`
- `modules/services/jellyfin/runtime.nix`
- `modules/services/navidrome/manifest.nix`
- `modules/services/navidrome/runtime.nix`

This axis opts Jellyfin, Seerr, and Navidrome into internet reachability,
replaces browser-centric OIDC with each application's native per-user account
model where native clients require it, disables unauthenticated Navidrome
sharing, and records account-hardening/setup guidance. The second commit
registers and activates Cloudflare DDNS on the entry-plane profile atomically
with the three routes. Review account lifecycle, Seerr import permissions, and
the removal of Navidrome OIDC as service behavior; review the inherited public
reachability against the networking axis.

## Evaluation tests

- **Review ref:** `pr/bank-tests` (`747d449`)
- **Landed range:** `2d0e086..2c2a9d7` (test paths selected from the mixed commit)
- **Preserved-only range:** `e949223..747d449` — **not landed**
- **Risk class:** **tests**

**Landed files:**

- `tests/eval/cloudflare-ddns-routes.nix`
- `tests/eval/lanroute-reachability.nix`

**Preserved ref changes, but main does not contain:**

- `tests/eval/cloudflare-ddns-routes.nix` (current module-path/API correction)
- `tests/eval/lanroute-reachability.nix` (retired fixture removal)
- `tests/eval/route-invariants.nix` (operator-internet and public-OIDC negative cases)

The landed fixtures intend to prove exact DDNS derivation and fail-closed Caddy
matcher lowering. They entered before the current-architecture corrections and
still reference retired placement/service APIs; the direct-eval validation that
passed was run from the preserved ref, not from the landed files. The landed
range also does not extend `route-invariants.nix`, and `flake.nix` was explicitly
excluded, so these new files are not wired into the flake check set. Treat test
coverage as incomplete until the preserved correction is reviewed and landed.

## Plans and documentation

- **Review ref:** `pr/bank-plans-docs-clean` (`2379f18`)
- **Landed ranges:** `2d0e086..2c2a9d7` (docs/plans paths selected),
  `e61cee8..2379f18`, and `2379f18..bd89038`
- **Risk class:** **docs**

**Files:**

- `README.md`
- `docs/PROJECTS.md`
- `docs/decisions/0000-rationales.md`
- `docs/decisions/0004-letsencrypt-on-home-phibkro-org.md`
- `docs/decisions/0006-family-media-internet-entry.md`
- `docs/generated/lan-route.md`
- `docs/plans/2026-06-21-improve-audit.md`
- `docs/plans/2026-07-19-public-status-and-maintenance.md`
- `docs/reference/network.md`
- `docs/roadmap.md`
- `plans/README.md`
- `plans/001-isolate-pavilion-sops.md`
- `plans/002-rotate-console-credentials.md`
- `plans/003-enforce-real-unit-hardening.md`
- `plans/004-authenticate-suwayomi-api.md`
- `plans/005-place-replica-intent-on-target.md`
- `plans/006-fail-closed-backup-runtime-tests.md`
- `plans/007-resolve-manual-backup-units.md`
- `plans/008-run-replica-verifiers-now.md`
- `plans/009-claim-music-before-ingest.md`
- `plans/010-fail-closed-observability.md`
- `plans/011-gate-third-party-agent-skills.md`
- `plans/012-verify-authelia-client-registry.md`
- `plans/013-repair-active-documentation.md`
- `plans/014-single-runtime-test-environment.md`

This axis records ADR-0006, updates active and generated network guidance,
retains the earlier public-status plan as a superseded precursor, adds router
acceptance work to the roadmap, and lands a 14-plan audit backlog generated
against the older `0cef85b` tree. `docs/PROJECTS.md` also receives the two
intended succession-handoff updates that bracketed the accidental sweep. Review
the ADR and active network docs for agreement with code; treat the root `plans/`
files as historical advisor handoffs whose drift checks and paths must be
revalidated before execution.

## Pre-deploy review order

1. Networking / entry plane — prove default-deny and exact DNS ownership first.
2. Family media services — verify only the intended three routes opt in and
   native accounts are ready.
3. Evaluation tests — correct and wire the landed fixtures before relying on
   them as evidence.
4. Home / operator tooling — wire the JUCI skill only after privileged procedure
   review.
5. Plans/docs — reconcile claims against the reviewed code; do not execute stale
   root plans mechanically.
