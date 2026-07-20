# Hyprland session persistence — event-log capture, tmux-style named restore

Status: draft for review · 2026-07-20
Origin: one-shot restore script built for the 2026-07-20 reboot (broken StreamCam
cable) proved the mechanics; this generalizes it into a permanent facility.

## Problem

A reboot (or Hyprland crash) discards the desktop's working set: which apps were
open, on which workspace/layer, playing what. Rebuilding it by hand costs minutes
and forgets things. tmux solved this shape for terminals: sessions persist, are
named, and survive detach — we want the desktop-window analogue, accepting that
app-internal state (shell contents, playback position) is out of scope.

## Goal

After any reboot or crash, `hypr-session restore` reproduces the window layout —
right apps, right workspaces/layers, right launch commands — from a snapshot no
older than the last window-state change. Sessions can be pinned under a name,
listed, renamed, and restored selectively, like tmux sessions.

## Constraints

- **Lua-mode dispatch syntax.** All `hyprctl dispatch` calls must use the
  `hl.dsp.*` builder form (gotcha-hyprland-lua-migration). Verified working:
  `exec_cmd` with spawn-time workspace target, by-address `window.move`.
- **No static app→tag window rules** — deliberate rice decision. Placement must
  happen at spawn time (workspace target) or post-spawn (by-address move), never
  via rules.
- **Login PATH is thin** (no jq). Every runtime dependency is closed over by Nix
  wrapping, same as the existing layer-toggle/layer-cycle scripts.
- **Shutdown ordering is not trustworthy.** Any design that runs capture *during*
  shutdown races Hyprland's death. The design must not depend on a shutdown hook
  firing.

## Values

- Correct by construction over detected: the shutdown race is designed out, not
  handled.
- One construct: reuse the layer-tag vocabulary and the hypr-rice script-packaging
  pattern; no parallel session concept.
- Best-effort restore, loud about gaps: anything unrestorable is reported, never
  silently dropped.

## Domain framing

This is a **database problem, not a process problem**: state outlives any
runtime (durability), unlike tmux/Herdr where the runtime *is* the state
(uptime). Consequences that are decisions, not defaults: the log records **full
snapshots, never deltas** — our replayers (apps) are non-deterministic, so
delta-folding has no sound apply operation; and the crash guarantee ("snapshot
≤ one debounce-window stale") is an RPO bound. Do not "optimize" the log into
an event-delta stream — that trades away the only correctness property the
non-deterministic apply leaves us.

## The right answer, and why not

The state-of-art is the Wayland **xdg_session_management** protocol
(wayland-protocols, 2025): compositor and apps cooperatively persist true session
state, including app internals. That is the correct long-term home for this
problem. Cost today: Hyprland support and toolkit adoption are immature/absent —
not reachable. Community Hyprland session tools exist (poll-based) but are thin
wrappers over the same `hyprctl clients` data with none of our lua-mode/layer
specifics. So: bespoke, but with the restore engine behind an adapter seam so a
future protocol implementation can replace it without touching capture or CLI.

## Architecture

```text
Hyprland socket2 (IPC events)
  openwindow / closewindow / movewindow / workspace …
        │
        ▼  (debounced ~2s)
┌────────────────────┐     append      ┌──────────────────────────────┐
│ hypr-session-logd   │ ──────────────► │ ~/.local/state/hypr-session/ │
│ systemd user service│                 │   log.jsonl   (bounded ring) │
│ part of graphical-  │                 │   named/<name>.json          │
│ session.target      │                 └──────────────────────────────┘
└────────────────────┘                        ▲            │
                                         save/rename       │ read
                                              │            ▼
                              ┌───────────────────────────────┐
                              │ hypr-session CLI               │
                              │  list · save · rename ·        │
                              │  restore [name] · prune        │
                              │  └─ restore engine (adapters)  │
                              └───────────────────────────────┘
```

### Capture — event log, not shutdown hook

`hypr-session-logd` subscribes to Hyprland's socket2 event stream. On any
window-topology event (debounced), it appends a full snapshot to `log.jsonl`.
The **last log entry is always the pre-shutdown state by construction** — no
shutdown hook exists to race. Crash coverage falls out for free: worst case, the
snapshot is one debounce-window stale.

A snapshot enriches `hyprctl clients -j` per window with what restore needs and
`hyprctl` doesn't provide: process cmdline and cwd (from `/proc`), captured at
snapshot time while the pid is alive. Floating geometry is captured; monitor
layout recorded for future multi-monitor correctness (current rig: one monitor).

The log is a bounded ring (size/count cap, pruned by the daemon) — an event log
for recovery and history, not an unbounded journal.

### Sessions — tmux mapping

| tmux | hypr-session |
| --- | --- |
| implicit current session | head of `log.jsonl` ("last") |
| `new -s name` / pin | `save <name>` — freezes current snapshot to `named/<name>.json` |
| `rename-session` | `rename <old> <new>` |
| `ls` | `list` — named sessions + last-auto timestamp |
| `attach -t name` | `restore <name>` (default: last) |

Restore does not kill existing windows (tmux attach doesn't either); it spawns
what the snapshot describes. A `--diff` flag prints what would be launched
without doing it.

### Restore engine — adapters

Default path: for each captured window, respawn its recorded cmdline into its
recorded workspace via spawn-time targeting; reapply floating geometry.

A small **adapter table** (class → strategy) handles apps whose window model
breaks the one-window-one-process default; this is the single home for all
app-specific knowledge:

| Class | Strategy |
| --- | --- |
| `code` | launch once; VS Code restores its own windows; move each to its captured layer by address, matched on identity (project folder — see Herdr notes) |
| `zen-beta` | launch once; own session restore covers tabs/windows; move windows to captured layers |
| `com.mitchellh.ghostty*` | respawn per window with captured cwd; shell contents acknowledged lost |
| (default) | respawn recorded cmdline per window |

Windows whose origin can't be reconstructed (no cmdline captured, pid was gone)
are listed in the restore report as manual follow-ups — loud, not skipped.

### Packaging

Everything lives in `modules/home/desktop/hypr-rice/`: two Nix-wrapped scripts
(daemon + CLI) with closed-over dependencies, one systemd user service
(`WantedBy=graphical-session.target`), state under XDG state dir. Optional:
expose `restore`/`save` through the existing rice-command palette.

## Out of scope (named, not painted over)

- App-internal state (shell history/contents, media position, unsaved buffers).
- Automatic restore-on-login (explicit `restore` first; can become an opt-in
  login unit once trusted).
- Multi-monitor placement logic (captured, not yet acted on).
- Filtering dead/stale windows at capture time — restore is snapshot-faithful;
  exclusion is a restore-time choice (`--diff`, then selective).

## Design notes from Herdr (researched 2026-07-20, v0.7.4 on disk)

Herdr's multiplexer state model was read directly from its persisted artifacts
(`~/.config/herdr/session.json`, schema version 3; `sessions/<name>/` each with
own socket + state) and its CLI surface. What transfers, what doesn't:

### The fundamental divergence: attach vs replay

A Herdr/tmux session survives because a **server owns the processes** — detach
is not death, and "restore" is reattaching to something still alive. A
compositor session has no such server: windows die with Hyprland, so our
restore is **replay** (respawn from a description), inherently best-effort.
This is why we need the adapter table and Herdr doesn't: their pane unit has
one uniform resurrection recipe (spawn shell at cwd); desktop windows have one
per app. Everything below adopts Herdr's ideas *around* this gap, not across it.

### Adopted

| Herdr practice | Our adoption |
| --- | --- |
| Versioned state schema (`"version": 3`) | Snapshots carry a `version` field from day one; restore refuses versions it doesn't know |
| Persist only reconstructable facts (pane → `cwd`, never scrollback) | Confirms our app-internal-state exclusion; per-window we keep exactly what respawn consumes |
| Explicit **identity block** per unit (`identity_cwd`, `worktree_space`: repo root / checkout path / linked flag) | Each captured window gets an `identity` field (terminal → cwd, editor → project folder, media → file) distinct from raw cmdline. Adapters match and label on identity, not title regexes — kills the brittle VS Code title-match in the current draft |
| `custom_name` nullable; labels derive from identity when unset | Named sessions are a label in snapshot metadata, auto-labels derive from identity (e.g. dominant project cwd) — not filesystem-name-as-identity |
| Focus is session state (`active_tab`, `focused`, `zoomed`) | Capture shown special + focused window; restore ends by showing them. A session is *where you were looking*, not just what existed |
| Continuous write-on-change, no shutdown hook | Independent confirmation of the event-log capture decision |
| CLI prints JSON; consumers read state, never predict it | `hypr-session` subcommands get `--json`; the restore report is data first, prose second (palette/tooling can consume it) |

### Considered, not adopted

| Herdr practice | Why not |
| --- | --- |
| One canonical current-state file instead of a history ring | Their server can't lose state it owns; we *can* (crash mid-churn, bad restore). The ring buys point-in-time recovery for ~zero cost. Adopt the shape though: `current.json` as the always-valid head, ring as history behind it |
| Persisted public ID counters (stable, never-reused pane numbers) | Solves cross-restart *addressing* of live units. Our windows get fresh Hyprland addresses on every respawn and nothing external addresses them between sessions — no consumer, no counter |
| Per-session directory with own socket/server | Follows from attach-vs-replay: we have exactly one compositor, sessions are data not processes. `named/<name>.json` suffices |
| Recursive layout tree per tab (`layout`, split geometry) | Hyprland retiles on spawn; capturing the split tree buys fidelity only if restore replays split order — deferred with multi-monitor, revisit if retile placement proves annoying |

## Definition of Done

1. Reboot → `hypr-session restore` reproduces the layout: every restorable
   window on its captured workspace/layer, verified against a fresh
   `hyprctl clients` diff.
2. Kill Hyprland uncleanly → last log entry is ≤ debounce-window old.
3. `save`/`rename`/`list`/`restore <name>` round-trip a named session.
4. Log ring respects its bound under sustained window churn.
5. Restore report names every window it could not restore.
6. `nix flake check` green; scripts carry their deps (run from a clean PATH).
