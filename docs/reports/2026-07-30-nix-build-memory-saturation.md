# 2026-07-30 incident: an unbounded `nix build` gets 211 agent processes killed

**TL;DR** — An agent ran `nix build .#aeneas .#charon`. `max-jobs` was unset, so it resolved to
`auto` = 12 concurrent derivations; one of them (`ocamlPackages.saturn`'s `checkPhase`) runs
**dscheck**, an exhaustive interleaving model checker whose state space grows without bound. That
builder reached 1.77 GiB RSS + 3.0 GiB swap in 13 min, still climbing. The box went into swap
thrash and `systemd-oomd` killed **6 herdr pane scopes / 211 processes** — including a 4-day
claude session and a 19-hour codex session — while the build that caused it was never a
candidate. Recovery happened only because the sixth kill destroyed the pane that *owned* the nix
client, aborting the build as a side effect of destroying the victim.

The kernel OOM killer never fired (`memory.events oom_kill = 0`). This was entirely
`MemoryHigh` throttling feeding oomd's PSI trip.

## Timeline (CEST)

| Time | Event | Evidence |
|---|---|---|
| ~00:47 | `nix build .#aeneas .#charon --print-build-logs` starts in pane `wP:pN` (agent `aeneas-probe-sonnet`, cwd `/tmp/semantic-aeneas-feasibility-0009.hIwYBf`) | `/proc/341580/cmdline`, ancestry to `herdr` pid 88850 |
| 00:59:18 | **saturation alert fires**: `full_avg300=18.18%` (limit 10%), `some_avg10=24.05%`, swap 49%, tasks 3154 | `saturation-alert.nix` |
| 01:03:15 | **First oomd kill** — `herdr-wP-p1-3495053.scope`, 41 procs (19 h codex) | `journalctl -u systemd-oomd` |
| 01:04:26 | `herdr-wP-pQ-938533.scope`, 26 procs | same |
| 01:04:42 | `herdr-wJ-pT-2555397.scope`, 36 procs (2 d 22 h codex) | same |
| 01:04:56 | `herdr-w4-p1-106461.scope`, 14 procs | same |
| ~01:05:02 | Peak: global `full avg10 = 54.66%`, `some avg10 = 74.46%`, `sy = 88–91%`, `si` up to 53 MB/s, 57–60 runnable / 13–17 blocked. nixbld footprint 5.1 GiB; agents ~12.5 GiB RSS | live sampling, `vmstat` |
| **01:05:04** | **Operator freezes the build** — `SIGSTOP` on uid `nixbld2`, `nixbld13`. Verified freeze-safe first: `max-silent-time=0`, `timeout=0`, so nix waits rather than fails | `sudo` audit trail in journal |
| 01:05:11 | `herdr-w6-pD-4102543.scope`, 50 procs — **4 d 7 h claude**, 5 G mem peak / 2.5 G swap peak (oomd had already marked it) | user journal `Consumed` line |
| 01:06:04 | Global pressure recovers: `full avg10` 54.66% → **2.76%** | live sampling |
| 01:08:47 | **`herdr-wP-pN-333783.scope`, 44 procs — the build's OWNER.** Killing it took the nix client with it, so nix-daemon aborted the build | journal |
| ~01:11 | Steady state: `user-1000.slice full avg10 = 0.00%`, MemAvailable 12.3 GiB, swap 9 GiB | live sampling |

## Root cause chain

```
agent aeneas-probe-sonnet (pane wP:pN)
  └─ nix build .#aeneas .#charon           max-jobs unset → auto = 12, cores = 0 → all 12
       └─ nix-daemon (system.slice, NO memory ceiling) fans out 12 derivations
            ├─ nixbld2  dune runtest -p saturn -j 12
            │    └─ dscheck_htbl.exe   1.77 GiB RSS + 3.00 GiB swap, still climbing
            ├─ nixbld13 cargo-miri → miri            670 MiB
            └─ nixbld1  cargo → 12x concurrent rustc  ~2.3 GiB
                    ↓
   pushes user-1000.slice past herdr.slice MemoryHigh = 12 GiB
                    ↓
   kernel throttle-reclaims INSIDE the agent slice (herdr.slice memory.peak
   12.53 GiB against its 12 GiB cap)
                    ↓
   sustained reclaim → user-1000.slice PSI > 50% for > 30 s
                    ↓
   oomd kills in user.slice; system.slice is not even monitored
                    ↓
   agents die, cause persists → cascade of 6 kills over 5 m 32 s
                    ↓
   kill #6 happens to own the nix client → build aborts → cause removed
   AS A SIDE EFFECT of destroying the victim
```

### The structural insight

**PSI is charged where the stall happens, not where the allocation happened.** The build took
shared RAM without stalling itself:

| cgroup | full-pressure during incident | oomd status |
|---|---|---|
| `system.slice` (nix-daemon — the culprit) | **avg300 = 0.32%** | **not monitored at all** |
| `user-1000.slice` (the agents — the victims) | avg300 = 23.01% | monitored, `kill` @ 50% |

So pressure-based victim selection **structurally cannot** target a cgroup that steals memory
without stalling itself. Even if `system.slice` had been monitored at 60%, 0.32% would never have
tripped. The only mechanism that works is a **ceiling on the allocation**, not a trigger on the
stall.

### Contributing defect 1 — `resource-tiers.nix` is orphaned dead code

`modules/infra/resource-tiers.nix` declares per-service `MemoryHigh`/`MemoryMax` tiers plus
`enableSystemSlice = true`. **It is imported by no host.** Verified: no file references
`resource-tiers`; `nori.resourceTier` is absent from `config.nori` on both workstation and aurora;
`systemd.oomd.enableSystemSlice` evaluates to `false`; no `/etc/systemd/system/system.slice.d`
drop-in exists; `oomctl` monitors only `/user.slice` and descendants.

It also wrote to `services.systemd-oomd.*`, an option path that does not exist (the real one is
`systemd.oomd.*`). That never surfaced as an eval error precisely *because* nothing imports the
file — adopting it as written would have failed immediately.

**Why it was never caught:** the flake's completeness lint globs
`modules/infra/<X>/default.nix` (flake.nix ~1088). This is a *flat* file, invisible to that
check. The lint can catch a directory-shaped concern missing a recipe; it cannot catch a module
nobody imports.

### Contributing defect 2 — `herdr.slice MemoryHigh = 12 GiB` is the amplifier

Four claude sessions at 2.3–3.8 GiB each ≈ 12 GiB, so the fleet sits *permanently at its throttle
ceiling* (`memory.peak` 12.53 GiB). Steady state is one allocation away from a reclaim storm, and
any extra load converts directly into PSI rather than into swap. This is the fourth trip in ten
days (07-20, 07-23, 07-27, 07-30).

### Contributing defect 3 — swap topology inverts its own purpose

`zram0` 15.6 GiB at priority **5** sits above a 32 GiB swapfile at priority **-2**, with
`swappiness = 60`. zram is *compressed RAM*: under genuine pressure it consumes the RAM it exists
to free (7.4 GiB resident at incident time). 47 GiB of total swap on a 31 GiB box converts what
should be a fast single-victim OOM kill into a ten-minute box-wide stall.

## What worked

- Per-pane scopes (2026-07-20 follow-up #1) held: kills were one lane each, not 908 processes in
  one shot. Blast radius per event was 14–50 procs instead of the whole fleet.
- `max-silent-time=0` / `timeout=0` made `SIGSTOP` a safe intervention — nix waits indefinitely
  rather than failing a frozen build.
- No kernel OOM, no freeze, no power-button. Desktop stayed responsive.

## What didn't

1. **Wrong victim, structurally guaranteed** — the culprit's cgroup was unmonitored *and*
   registered near-zero pressure. Six agent scopes died to relieve pressure they didn't cause.
2. **No ceiling anywhere on the system side** — `resource-tiers.nix` was supposed to be that, and
   is inert.
3. **`max-jobs` unbounded** — `auto` = 12 derivations x `cores = 0` = all 12 threads, on a box
   whose user slice is already budgeted at 24–28 GiB.
4. **Operator response watched the wrong metric** — `/proc/pressure/memory` (global) recovered
   54.66% → 2.76% in 60 s while oomd judges `user-1000.slice` PSI, which stayed hot for minutes
   as the agents' swapped-out pages faulted back in. That recovery thrash is what killed the
   owner at 01:08:47, 3 m 43 s *after* the freeze. Four of six kills preceded the freeze entirely.

## Casualties

| Scope | Procs | Session | Age |
|---|---|---|---|
| `herdr-wP-p1-3495053` | 41 | codex | 19 h |
| `herdr-wP-pQ-938533` | 26 | codex | 2 m |
| `herdr-wJ-pT-2555397` | 36 | codex | 2 d 22 h |
| `herdr-w4-p1-106461` | 14 | — | — |
| `herdr-w6-pD-4102543` | 50 | claude | **4 d 7 h** |
| `herdr-wP-pN-333783` | 44 | claude `aeneas-probe-sonnet` | 29 m |

Codex sessions resume via `codex resume <id>` in the matching cwd; claude sessions resume.
Completed derivations remain in `/nix/store`, so the aeneas/charon build resumes rather than
restarts.

## Fixes applied

`machines/workstation/default.nix` — the ceiling, as the FOURTH CALIBRATION alongside the
existing user-side caps:

```nix
systemd.services.nix-daemon.serviceConfig = {
  MemoryHigh = "4G";      # load-bearing: build reclaims its OWN pages, not the fleet's
  MemorySwapMax = "8G";   # throttling cannot become unbounded disk thrash
  MemoryMax = "12G";      # runaway backstop, above any legitimate derivation here
};
nix.settings = { max-jobs = 4; cores = 3; };   # 4 x 3 = 12 threads on 12 cores
```

`MemoryHigh` is the one that matters: it re-points reclaim cost at the build instead of at
innocent agents, without ever failing a legitimately hungry derivation. `MemoryMax` only catches
true runaways; upstream already sets `OOMPolicy=continue` and nix-daemon is ~20 MiB against a
multi-GiB builder, so `oom_score` always selects the builder and the daemon survives.

`infra/resource-tiers.nix` — corrected `services.systemd-oomd` → `systemd.oomd`, and documented
the orphan status prominently so the file stops reading as an active guarantee.

## Verification (rebuilt + activated 2026-07-30 01:34)

Live enforcement confirmed at the kernel, not just in the unit file:
`memory.high = 4.00 GB`, `memory.swap.max = 8.00 GB`, `memory.max = 12.00 GB`,
`max-jobs = 4`, `cores = 3`.

Then the real journey — a derivation allocating 16 GiB, run through the actual daemon:

```
 4s  RSS pins at exactly 4.00G   <- MemoryHigh engaged, throttle counter climbing
 4->34s  RSS steady at 4.00G while swap climbs 0.13 -> 7.86G
36s  swap pins at exactly 8.00G  <- MemorySwapMax enforced
36->60s  both axes capped; RSS creeps 4.07 -> 4.16G
throughout: user-1000.slice full avg10 = 0.00%, MemAvailable steady ~18.5 GiB
```

**The incident inverted.** A 16 GiB build was held to 4 GiB resident + 8 GiB swap entirely inside
its own cgroup and the agent fleet felt *zero* pressure — against 23% PSI and six dead scopes on
the night of the incident.

Honest limits of this verification:

- The `MemoryMax` OOM path was **not** observed. A 7 GiB allocation against a temporarily lowered
  5 GiB max with swap disabled ran 300 s without tripping it (`max=0`, `oom_kill=0`,
  `high=55647`) — `MemoryHigh` throttling slows the builder faster than it can climb. MemoryMax is
  insurance; MemoryHigh is the mechanism. The daemon PID was unchanged throughout, so the
  "daemon survives" half is confirmed; the "builder gets killed" half is not.
- The temporary runtime override was reverted and re-verified back to 4G / 8G / 12G.
- One false green caught en route: the first kill-path attempt returned exit 0 because the
  derivation was already in `/nix/store` from a prior run — nothing executed. `max=0` there meant
  "nothing ran", not "nothing was killed". Re-run with a fresh derivation hash.

## Follow-ups (decisions, not cleanups)

| # | Action | Notes |
|---|---|---|
| 1 | **Adopt or delete `resource-tiers.nix`** | Adopting needs per-host import + tier assignments + recalibration (its comment says "~64 GB workstation"; the box has 31 GiB). `enableRootSlice` sets `ManagedOOMSwap=kill` on the ROOT slice — adopt deliberately. |
| 2 | **Close the orphan-module lint gap** | Extend the flake check to assert every `modules/infra` file declaring `options.nori.*` is reachable from some host's module list. This is the *test* rung that would have caught defect 1 — currently convention-only. |
| 3 | **Raise `herdr.slice` budget or cap fleet size** | Coupled: raising `MemoryHigh` above 12 GiB requires raising `user-1000.slice` too, or it eats the desktop's ~12 GiB share. The alternative is fewer concurrent resident sessions. |
| 4 | **Shrink zram** | `zramSwap.memoryPercent` ≈ 25 (from the 50% default) so compressed pages stop competing for the RAM they free. Set in `machines/base/base.nix`. |
| 5 | **Recycle long-lived agent panes** | Two casualties were 3–4 days old at ~3 GiB. Agent RSS grows monotonically with accumulated context; `CLAUDE.md` caps delegation concurrency but not total resident sessions. |
| 6 | **Point the saturation alert at the cgroup oomd judges** | It fired on global `full_avg300`; oomd acts on `user-1000.slice` PSI. Alerting on the deciding metric buys lead time before the first kill. |
| 7 | **Make a throttled runaway fail loud** | New consequence of the fix, measured above: a runaway no longer takes the box down, it crawls at 4 GiB + 8 GiB swap *forever*, and `max-silent-time`/`timeout` are both 0 so nothing surfaces it. Needs a `max-silent-time` generous enough for this host's longest legitimately-silent build — that number isn't known yet, hence a decision rather than an edit. |

## Rebuild note

`just rebuild` is itself a large parallel nix build and would reproduce this incident while
`user-1000.slice avg300` is still decaying. Apply these changes when agents are quiesced, and
drive the first rebuild with `--max-jobs 2 --cores 4`.

Related: [2026-07-20 oomd agent fleet kill](2026-07-20-oomd-agent-fleet-kill.md) — this is that
report's deferred follow-up #5 (victim steering), plus a new system-side gap it never considered.
