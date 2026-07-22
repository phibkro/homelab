# 2026-07-20 incident: systemd-oomd kills the entire agent fleet (908 processes, one scope)

**TL;DR** — At 00:19:45 systemd-oomd killed `app-ghostty-surface-transient-1970273.scope`
— the single ghostty surface hosting the main Herdr server and, transitively, nearly the
whole agent fleet (908 processes). The July-9 guardrail (`MemorySwapMax=16G` on `user@1000`
+ oomd on user slices) **worked as designed**: the desktop survived, no hard freeze, no
power-button. What it exposed is a blast-radius problem: the fleet lived in ONE cgroup, so
the smallest killable unit was *everything*.

Herdr did not crash on its own; it was OOM-killed. Zen closing "finally" right after is the
tell: its close request had been queued behind a swap-in storm, and once oomd freed ~19 GiB
the UI thread got scheduled and exited cleanly.

## Timeline (CEST)

| Time | Event | Evidence |
|---|---|---|
| Jul 4–8 | Baseline: k10temp daily avg ~49 °C | VictoriaMetrics `node_hwmon_temp_celsius` |
| Jul 9 → | Agent-fleet era: temps 55–65 °C daily avg, sustained high load | same; correlates with CPU busy%, not cooling degradation |
| ≤ 20:23 (Jul 19) | `hyprpaper` begins ABRT crash-loop every ~12 s (unrelated, still looping after recovery) | user journal |
| 00:09 | Pre-incident snapshot: load 56 (12 cores), zram 15.6/15.6 GiB **full**, slice swap **15.9/16 GiB — at `MemorySwapMax` cap**, CPU PSI some ≈75 %, IO PSI some ≈72 %, `kswapd0` runnable | this session's live sampling |
| 00:09 | Holders: zen 4.3 GiB RSS + **10.9 GiB swap** (3.9 d uptime, unresponsive); 8 idle codex sessions **5.9 GiB swap**; 6 active claude sessions ~9 GiB RSS (verified working, 22–156 % CPU); 2 concurrent `lake build` + `nix flake check` | ps/proc sampling |
| ~00:10–00:19 | Operator repeatedly requests zen close → paging its ~11 GiB back from disk swap joins the thrash; reclaim storm (scope Pgscan 628 M pages), pressure climbs; load 1-min peaks ~92 | oomd candidate dump; load avgs |
| 00:19:43 | oomd marks the ghostty scope: memory pressure **61.84 % > 60 % limit for > 30 s** with reclaim activity; scope usage 19.4 GiB | `journalctl -u systemd-oomd` |
| 00:19:45 | **908 processes killed.** Scope had consumed 3 d 5 h CPU, 19.7 GiB mem peak, 11.6 GiB swap peak | user journal `Consumed` line |
| ~00:22 | Zen finishes its queued shutdown. System recovered: 12 GiB used, swap 10 GiB total, slice swap 4.0 GiB | free/swapon/systemctl |
| ~00:21+ | Operator restarts Herdr (fresh server); this Claude session resumed (its previous pid 3002304 was among the killed) | pgrep |

## Root cause chain

```
zen: 10.9 GiB swap, idle 3.9 d ─┐
8 parked codex: 5.9 GiB swap ───┼─► slice swap budget (16 GiB) fully
                                │   consumed by SQUATTERS, active fleet
                                │   forced to thrash zram+disk
2 lake builds + flake check ────┼─► CPU 4× oversubscribed (load 56/12),
+ 6 active claude sessions      │   IO PSI ~72 % — reclaim can't keep up
                                │
zen close attempt ──────────────┴─► mass swap-in storm → pressure in the
                                    fleet's scope > 60 % for 30 s → oomd kill
```

Structural amplifier: **one ghostty surface = one transient scope = one oomd target.**
Herdr server + every pane + every agent + every build shared a single cgroup, so oomd's
per-cgroup kill semantics turned "relieve pressure" into "kill the fleet". oomd also
considered only this one candidate — the *squatters* (zen, in its own scope) were not
evaluated for the kill even though they held more swap.

## What worked

- The 2026-07-09 patch (`MemorySwapMax=16G` on `user@1000.service` + `systemd-oomd` on
  user slices) is **verified live and did its job**: contained the failure inside the user
  slice, desktop stayed responsive, clean recovery in ~3 min. Contrast: Jul 9 needed a
  power-button.
- No kernel OOM, no data-loss surface: codex sessions persist under `~/.codex/sessions`
  (resumable), claude sessions resume, `/tmp` build checkouts intact, git worktrees clean.

## What didn't

1. **Blast radius** — smallest killable unit was 908 processes (fleet-in-one-scope).
2. **Wrong victim** — the squatting browser survived the kill decision; the working fleet died.
3. **Swap-squatter accumulation** — ~16.8 GiB of the 16 GiB budget was held by processes
   doing nothing (zen idle tabs + parked codex TUIs).
4. **Uncoordinated heavy gates** — two `lake build`s + `nix flake check` each assumed they
   owned all 12 cores.
5. **`hyprpaper` ABRT crash-loop** (≥ 4 h, every ~12 s, ongoing) — separate defect; journal
   noise + restart churn; 16 MiB peak so not a memory contributor.

## Casualties (all recoverable)

Codex sessions (resume with `codex resume <id>` in the matching cwd):

| Session id | cwd | Task (first prompt) |
|---|---|---|
| `019f767b-…6fce38` | homelab | Jellyfin/media expansion for family (already resumed post-incident) |
| `019f71fc-…c65333` | semantic-packages | continuation of a ChatGPT design chat |
| `019f7808-…822c63` | semantic-packages | same thread, second lane |
| `019f7257-…fc6da2` | lang-bang | cross-conversation insight synthesis |
| `019f7532-…da186` / `…bcda7` | lang-bang | worker lanes (plugin-prompt first line; task assigned later in-session) |
| `019f7b66-…794158` | lang-bang-eng | implement issue #186 (Plan 014 P4.5 role lab) — was ACTIVE |
| `019f75ed-…bcc433` | projects | orchestration-lifecycle terminology analysis |
| `019f7b67-…818113`, `019f7808-…5847aa`, `019f7532-…9851cd` | (various) | pagu-box action-judge helpers (ephemeral, no resume needed) |

Claude panes: all Herdr-hosted sessions died (incl. the 25 h+ plan-mode reviewers at
~2.2 GiB each and this session's predecessor); one non-Herdr session (pts/0, 3.9 d) and
this resumed session survived. In-flight `lake build` ×2 and `nix flake check` were killed;
re-runnable.

## Follow-ups

| # | Action | Mechanism |
|---|---|---|
| 1 | **Shrink the blast radius** — one scope per lane, not per fleet | launch Herdr panes/workspaces via `systemd-run --user --scope` (wrapper or Herdr feature); oomd then kills one lane |
| 2 | Evict swap squatters routinely | close parked codex panes when a lane ends (state persists on disk); restart zen at session boundaries instead of multi-day uptimes |
| 3 | Stagger heavy verify gates | `nice -n19` / bounded `-j` for `lake build` & `nix flake check`, or serialize via lane discipline |
| 4 | Fix or mask `hyprpaper` | it is still crash-looping; investigate core dump (`coredumpctl`), or disable until fixed |
| 5 | Consider oomd steering | `ManagedOOMPreference=avoid` on the fleet scope / `prefer` on browser scopes — biases victim selection toward the squatter |

## Addendum (same evening): the relaunched fleet escaped the guardrail entirely

The restarted Herdr server (launched from a login-session shell) landed in
`session-3.scope` — a **sibling** of `user@1000.service`, where every cap and oomd
setting above does not apply. 12+ GiB of fleet ran with zero containment until runtime
caps were applied to `user-1000.slice` (the true user boundary, containing both the
session scopes and `user@`). Persisted in `workstation/default.nix`
(`systemd.slices."user-1000"`); the per-pane bash hook warns when a pane cannot
self-isolate and names the launch idiom that fixes it:
`systemd-run --user --scope --slice=herdr.slice herdr`.

Follow-up #1 (per-lane scopes) and #3 (lane CPU/IO yield) are implemented in
`workstation/home.nix`; #5 (browser `ManagedOOMPreference` steering) is deferred until
the in-flight wayland-session rework lands, since it owns how apps get their scopes.

Related: [2026-07-09 freeze forensics](../../docs) (session 527e7a4e), auto-memory
`workstation-freeze-claude-heap`, `session-economics`.
