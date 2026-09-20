---
summary: Runtime introspection tests for the homelab — when they pay
  off, where they live, and which `nori.<X>` effect each one covers.
  This is LAYER 3 of the testing methodology; see
  `docs/reference/testing-methodology.md` for the pyramid and when to
  reach for eval / nixosTest / runtime introspection.
---

# Runtime tests

The homelab's runtime tests are **introspection recipes**: query the
live system's registries (systemd, restic, Caddy, VictoriaMetrics,
Hyprland IPC) and assert the declared intent landed. They're not unit
tests — they verify that the multi-step transformation from nix
declaration to runtime effect didn't silently desync.

**This is layer 3 of the three-layer methodology.** Layers 1-2 (eval
and nixosTest) catch failures BEFORE deploy; runtime introspection
catches drift AFTER. See [`testing-methodology.md`](testing-methodology.md)
for the decision tree on when to reach for each.

## When introspection tests pay off

The pattern: **a declaration produces multi-effect derived state via an opaque transformation**. Four levers determine value, composed multiplicatively:

| Lever | What it captures | Maxes out at |
|---|---|---|
| **Leverage** | How many downstream effects one declaration produces | compiler-owned routes: Caddy, DNS, monitors, identity, and status |
| **Volatility** | How often the registry changes | manifest endpoints and Hyprland binds |
| **Opacity** | How silent a partial desync is | backups (silent until restore), observability (you don't know what you don't know) |
| **Blast radius** | Cost if desync goes undetected | backups (data loss), routes (auth bypass), observability (incident detection) |

One lever maxed = nice-to-have. Two = ship it. Three+ = required.

## Where the homelab's tests live, and what they cover

| Recipe | Effect under test | Module |
|---|---|---|
| `just test-hypr` | Hyprland config, key/modifier registration, dispatcher smoke checks, and rejected `hypr-layout` inputs with unchanged workspace state | `users/nori/programs/desktop/hypr-rice/` |
| `HYPR_RICE_LIVE_TEST=1 just test-hypr-layout-live` | Explicit controlled-window journey: stable-ID visual ordering, real spacer target, drift/reinsertion/replacement, special-workspace targeting, and absolute focused ratios | `users/nori/programs/desktop/hypr-rice/hypr-layout-live-test.sh` |
| `VICINAE_LAUNCHER_LIVE_TEST=1 just test-vicinae-launcher-live` | Private headless-Sway journey: desktop application and generated action indexing, extension loading, real launcher display, and command execution | `users/nori/programs/desktop/vicinae/vicinae-launcher-live-test.sh` |
| `just test-backups` | `nori.backups.<n>` → restic units exist + per-target snapshots ≤25h | `infra/common/nixos/backup.nix` |
| `just test-routes` | `lib.noriInventory.routes` → deployed Pi Caddy route + DNS + HTTPS | `inventory/default.nix` + Pi Ansible roles |
| `just test-observability` | VM scrape targets up + process-exporter publishing + Pi heartbeat <90s + zero failing Gatus probes | compiler Pi projection + `services/{gatus,victoriametrics}/ansible/` |
| `just test-replicas` | `nori.replicas.<n>` → per-replica verifier oneshot succeeded within freshness budget on the target host (smoke-passes on empty registry) | `infra/common/nixos/storage/replication.nix` |
| `just test-authelia` | projected OIDC clients → Pi Authelia active, healthy, correct issuer, and non-empty hashed secret files | `inventory/default.nix` + `services/authelia/ansible/` |
| `just test-music-ingest` | Disposable real-filesystem journey for claim, recovery, publication, conflict, and rejection behavior | `services/music-ingest/tests/runtime.sh` |
| `just test` | All non-destructive recipes above; the opt-in Ghostty geometry and headless launcher journeys are intentionally excluded | composite |
| `just test-self-hosted-firecracker` | Disposable transient KVM journey for a net-off Firecracker Environment. It checks exact create replay, guest isolation, drain rejection, stopped recovery, lease release, and cleanup. | `infra/workstation/firecracker-environment.nix` |

## The architectural correlation worth knowing

The pure inventory owns cross-host route intent. NixOS and Ansible modules
adapt that projection to runtime state. Runtime tests compare deployed state
with the compiler output. Nix-only Reader+Writer modules keep their existing
runtime checks.

| Authoritative source | Runtime adapter | Test | Test value |
|---|---|---|:-:|
| `infra/common/nixos/backup.nix` | NixOS restic units | `test-backups` | ★★★★★ |
| `inventory/default.nix` + workload manifests | Pi Caddy, Pi-hole, Gatus, Authelia | `test-routes`, `test-authelia`, `test-observability` | ★★★★★ |
| `infra/common/nixos/storage/replication.nix` | NixOS replica units | `test-replicas` | ★★★★ |
| `infra/common/nixos/service-hardening.nix` | ✓ `nori.harden` | — | ★★ (flake check is primary defence) |
| `infra/common/nixos/storage/default.nix` | ✓ `nori.fs` | — | ★★ |
| `infra/common/nixos/inventory.nix` | ✓ Read-only compiler projection | — | ★ (covered by inventory eval checks) |
| `infra/common/nixos/restart-policy.nix` | ✓ sweeps systemd | — | ★★ |
| `infra/common/nixos/motd.nix` | — config wrapper | — | n/a |
| `infra/common/nixos/gpu.nix` | — config wrapper | — | n/a |

Corollary: **adding a Reader+Writer mechanism to `infra/common/nixos/` commits to a runtime introspection test for it.** A plain host wrapper without that shape needs evaluation coverage, while a service or desktop realization belongs with its service or profile.

## Next potential test targets

These are the unshipped recipes the four-lever evaluation flagged as worth-doing-but-not-yet. Ranked by where the next incident is most likely to surface a gap they'd catch. **Ship one only when an incident touches its area** — building tests speculatively before then leaks into busywork.

| Recipe | What it would assert | Effect under test | Lever score | Trigger to ship |
|---|---|---|---|---|
| `test-harden` | For each `nori.harden.<n>`: declared `ProtectSystem/PrivateTmp/binds` actually applied to the systemd unit (`systemctl show` matches the option declaration) | `infra/common/nixos/service-hardening.nix` | leverage 3 · volatility 2 · opacity 3 · blast 3 | A hardening-bypass incident, or after the `every-service-has-fs-hardening` flake check is removed |
| `test-fs` | For each `nori.fs.<n>`: path exists, owner/mode/subvolume matches, AND entry exists in `nori.backups` or has an explicit excluded flag | `infra/common/nixos/storage/default.nix` | leverage 3 · volatility 1 · opacity 3 · blast 4 | The "I added a folder but forgot to wire backup" class — likely if user-data shape changes |
| `test-secrets` | For each `sops.secrets.<n>`: rendered file exists at expected path, mode/owner/group matches declaration, sops can decrypt with current key | sops integration | leverage 2 · volatility 1 · opacity 3 · blast 4 | Next sops key rotation, or any "service can't read secret" deploy break |
| `test-firewall` | Projected tailnet-only ports are subnet-bound and no unrelated ports are open | compiler Pi projection + firewall role | leverage 3 · volatility 1 · opacity 4 · blast 4 | After any change that adds a new exposed port |
| `test-network` | Pi-hole resolves every active route, MagicDNS resolves hosts, and subnet routes are advertised | inventory route projection + Tailscale | leverage 3 · volatility 1 · opacity 2 · blast 3 | After a subnet-route or DNS incident |
| `test-systemd` | Generic safety net — no failed units, all timers scheduled, no `bad-setting` states | cross-cutting | leverage 1 · volatility 4 · opacity 1 · blast 1 | (skip — `systemctl --failed` is already loud) |

**Pattern for shipping new tests:** when an incident occurs in an effect's area, the post-mortem question is "which test would have caught this?" If the answer maps to one of these unshipped recipes, that recipe becomes worth the ~50 lines of bash. Otherwise the framework's ratings predicted correctly that the recipe wasn't yet earning its keep.

## The evaluation axis (the four levers, reprised)

Restated so the criteria for future test decisions are explicit and reusable, not just embedded in the table at the top:

1. **Leverage** — how many downstream effects does one declaration produce? Multi-effect declarations have N seams where desync can hide; single-effect declarations have one (and are usually loud).
2. **Volatility** — how often does the registry change in practice? A high-volatility registry compounds risk per touch; a stable one earns tests reactively after the first surprise.
3. **Opacity** — how silent is a partial desync? Snapshot freshness, OIDC client presence, scrape-target health all silently degrade. Failed systemd units, DNS dropouts, missing volumes are loud.
4. **Blast radius** — what's the cost when undetected? Data loss (backups) and authentication bypass (routes) dominate; cosmetic configs don't.

Compose multiplicatively. One lever maxed makes a test nice-to-have. Two maxed = ship it now. Three+ = required.

A test that fails any one lever (e.g., low blast radius, even with high leverage) doesn't earn its bash. A test that maxes all four (`test-backups`) catches incidents nothing else does.

## Where introspection tests do NOT pay off

- **Already-loud-failing things.** Failed systemd units, network unreachability — the OS yells already; a test adds noise.
- **Build-time-only state.** `/nix/store` IS the test; impossible for declaration and existence to desync.
- **Single-step transforms.** One option → one env var is tautological to test.
- **Pure functions.** Nix-eval verifies them.

If you find yourself writing one of these, stop — you're testing the wrong layer.

## How tests fit the iteration loop

```
edit → fast checks + build + disposable tests
     → authorized live activation → relevant introspection → evidence
                                      ↓
                               failure → diagnose / approved rollback
```

Inspect each recipe before running it: introspection can include toggles and
other live effects. `just test` is the live composite; `just check-vm [name]`
uses disposable NixOS guests. Choose the affected checks for platform or Home
Manager changes. Do not discard operator edits when reverting a failed change.

The native layout geometry journey is intentionally outside that composite:
`HYPR_RICE_LIVE_TEST=1 just test-hypr-layout-live` creates uniquely named
regular/special workspaces and controlled Ghostty clients, including the actual
`glass-spacer`. It cleans exact addresses/PIDs under `EXIT`, `INT`, and `TERM`,
restores prior regular/special focus, reloads away dynamic test rules, and
verifies no disposable selectors remain. It prints the unique selectors and
each exact PID/address as they are created so interrupted cleanup is recoverable.

The launcher journey is also opt-in and does not use the operator's compositor.
`VICINAE_LAUNCHER_LIVE_TEST=1 just test-vicinae-launcher-live` starts Vicinae
on a private headless Sway socket. It uses disposable HOME and XDG roots. It
checks desktop application discovery, extension loading, and real window state.
It executes one generated action and one saved command with a literal argument.

## Real catches, for posterity

Each test was motivated by an incident it would have caught:

| Test | Real bug it caught (or would have) | When |
|---|---|---|
| `test-hypr` Tier 1+2 | popup-term silently broken since lua-mode migration (dispatcher syntax change) | 2026-06-07 |
| `test-hypr` Tier 3 + generated-Lua check | key/modifier registration drift; command mapping is generated because Lua dispatcher args are opaque to `hyprctl binds -j` | future-proofing |
| `test-backups` Tier 2 | navidrome `-onetouch` race left snapshot 32h stale (fixed by flock) | 2026-06-07 (same session) |
| `test-routes` Tier 1 | historic missing OIDC client during family-tier expansion | retroactive |
| `test-observability` Tier 1 | pi VM ingesting empty `namedprocess_*` series (PTRACE cap missing) | 2026-06-07 (caught earlier in session) |

Three real silent-failure-mode bugs surfaced in one session — all from
exercising the test surface, not from waiting for the next outage.
That asymmetry is the case for keeping these recipes load-bearing.

## References

- Hyprland test approach: [[just-remote-tailnet-hostnames]] (cross-host
  execution + [[hyprland-lua-mode-dispatcher-syntax]] for the trap
  that motivated `test-hypr`)
- Pattern C2 race: `[[pattern-c2-sqlite-race-flock]]` documents the
  navidrome-class bug `test-backups` catches
- `[[iteration-trio-workflow]]` for the `just show-option / set / activate-test /
  rebuild` companion CLI
