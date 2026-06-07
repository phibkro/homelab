---
summary: Runtime introspection tests for the homelab — when they pay
  off, where they live, and which `nori.<X>` effect each one covers.
---

# TESTING

The homelab's tests are **runtime introspection** recipes: query the
live system's registries (systemd, restic, Caddy, VictoriaMetrics,
Hyprland IPC) and assert the declared intent landed. They're not unit
tests — they verify that the multi-step transformation from nix
declaration to runtime effect didn't silently desync.

## When introspection tests pay off

The pattern: **a declaration produces multi-effect derived state via an opaque transformation**. Four levers determine value, composed multiplicatively:

| Lever | What it captures | Maxes out at |
|---|---|---|
| **Leverage** | How many downstream effects one declaration produces | `nori.lanRoutes` — 7 effects |
| **Volatility** | How often the registry changes | `lanRoutes` (new svc), Hyprland binds (per tweak) |
| **Opacity** | How silent a partial desync is | backups (silent until restore), observability (you don't know what you don't know) |
| **Blast radius** | Cost if desync goes undetected | backups (data loss), routes (auth bypass), observability (incident detection) |

One lever maxed = nice-to-have. Two = ship it. Three+ = required.

## Where the homelab's tests live, and what they cover

| Recipe | Effect under test | Module |
|---|---|---|
| `just test-hypr` | Hyprland keybind registry — declared `hl.bind(...)` → `hyprctl binds -j` reflects every (modmask, key) tuple | `machines/workstation/hyprland.lua` |
| `just test-backups` | `nori.backups.<n>` → restic units exist + per-target snapshots ≤25h | `modules/effects/backup.nix` |
| `just test-routes` | `nori.lanRoutes.<n>` → Caddy route + DNS + HTTPS reachable | `modules/effects/lan-route.nix` |
| `just test-observability` | VM scrape targets up + process-exporter publishing + pi heartbeat <90s + zero failing gatus probes | `modules/effects/gatus-probe.nix` + `modules/services/victoriametrics.nix` |
| `just test` | All of the above | composite |

## The architectural correlation worth knowing

**The homelab's testable surface is exactly the Reader+Writer-shaped subset of `modules/effects/` plus `home/`.** Every `nori.<X>` registry is a producer of effects whose runtime state can silently desync from the declaration. Everything else (`machines/`, `modules/common/`, service modules themselves) is either pure declaration (verified at nix-eval time) or loud-failing at runtime (no test needed).

| `modules/effects/` file | Reader-Writer shape | Test | Test value |
|---|:-:|---|:-:|
| `backup.nix` | ✓ `nori.backups` | `test-backups` | ★★★★★ |
| `lan-route.nix` | ✓ `nori.lanRoutes` | `test-routes` | ★★★★★ |
| `gatus-probe.nix` | ✓ embedded + standalone | `test-observability` | ★★★★★ |
| `harden.nix` | ✓ `nori.harden` | — | ★★ (flake check is primary defence) |
| `fs.nix` | ✓ `nori.fs` | — | ★★ |
| `hosts.nix` | ✓ Reader-only | — | ★ (used transitively) |
| `restart-policy.nix` | ✓ sweeps systemd | — | ★★ |
| `resource-tiers.nix` | ✓ Reader-only | — | ★ |
| `rust-motd.nix` | — config wrapper | — | n/a |
| `gpu.nix` | — config wrapper | — | n/a |

Corollary: **adding a new file to `modules/effects/` is implicitly committing to a runtime introspection test for it.** If the new file is a config wrapper without the Reader-Writer shape (rust-motd, gpu), it probably doesn't belong in `effects/` at all — it's just a service or desktop module that happens to live there for historical reasons.

## Where introspection tests do NOT pay off

- **Already-loud-failing things.** Failed systemd units, network unreachability — the OS yells already; a test adds noise.
- **Build-time-only state.** `/nix/store` IS the test; impossible for declaration and existence to desync.
- **Single-step transforms.** One option → one env var is tautological to test.
- **Pure functions.** Nix-eval verifies them.

If you find yourself writing one of these, stop — you're testing the wrong layer.

## How tests fit the iteration loop

```
edit  →  just preview  →  just test  →  just rebuild
                              ↓
                     fail → git checkout (revert)
```

Tests can be run against any generation. They're idempotent (paired
toggles where applicable, snapshot freshness checks where state-only).
The composite `just test` is the right precondition gate for any
deploy that touches `modules/effects/` or `home/`.

## Real catches, for posterity

Each test was motivated by an incident it would have caught:

| Test | Real bug it caught (or would have) | When |
|---|---|---|
| `test-hypr` Tier 1+2 | popup-term silently broken since lua-mode migration (dispatcher syntax change) | 2026-06-07 |
| `test-hypr` Tier 3 | "bind registered but pointing nowhere" class | future-proofing |
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
- `[[iteration-trio-workflow]]` for the `just option / set / preview /
  rebuild` companion CLI
