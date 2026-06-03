---
name: gotcha-systemd-restart-loop-bombs
description: USE WHEN adding `Restart=on-failure` to a systemd unit, or debugging cascading service outages after `nixos-rebuild switch` — a unit whose `ExecStart` fails fast respawns every RestartSec; cumulative pressure (FDs, GPU memory, scheduler) breaks the NEXT switch-to-configuration. Smoke-test ExecStart manually FIRST. `StartLimitBurst` doesn't protect against steady-state loops with restart intervals > window÷burst.
---

# systemd `Restart=on-failure` units are restart-loop bombs if `ExecStart` is wrong

A unit with `Restart=on-failure` + an `ExecStart` that fails fast (e.g. invalid CLI flag) will respawn every `RestartSec` seconds indefinitely (or until `StartLimitBurst` saves you). Each respawn pays the full cold-start cost of whatever the binary needs — for bwrap-wrapped tools that's a fresh namespace, a fresh nix-shell setup, and a fresh process tree. **Cumulatively, this can drain file descriptors, GPU memory, and scheduler capacity badly enough to break the NEXT `nixos-rebuild switch`.**

Hit 2026-06-03 with `systemd.user.services.claude-remote-control`: `ExecStart` passed `--dangerously-skip-permissions` to `claude remote-control` (server-mode subcommand rejects that flag — it's only valid for interactive `claude`). The unit looped at 10s intervals for 5+ minutes. When `nh os switch` ran, the system was under enough pressure that:

- `caddy.service` hit `Stopped with result 'timeout'` (couldn't shut down in the systemd timeout window)
- `wayland-wm@hyprland.service` same
- NVIDIA GPU returned `NV_ERR_NO_MEMORY` during the user-session re-init
- waybar logged `Too many open files`

When systemd force-kills units it considers stop-failed, `switch-to-configuration` treats them as "in transition" and **does not move to the start phase for them**. Net result: ~30 services stopped, never restarted. Including Blocky (DNS), Caddy (reverse proxy), Authelia (SSO), Immich, Jellyfin, qBittorrent, Vaultwarden, the *arr stack, Ollama, ntfy-publishers — the entire user-facing surface.

**The fix is structural, in the unit definition:**

1. **Smoke-test `ExecStart` BEFORE landing a unit with `Restart=on-failure`.** Manually invoke the exact command string (env, args, working dir) and confirm it succeeds — *especially* for sandboxed wrappers (claude-box, opencode-box) where the bwrap cold start hides quick failures behind a 50-300ms latency.
2. **Cap restart loops with `StartLimitIntervalSec` + `StartLimitBurst`** so an unverified unit can't loop forever. The claude-remote-control unit had `StartLimitBurst=5` in 300s — *but the loop kept running because each restart was scheduled OUTSIDE the burst window* (10s interval × 5 = 50s, well under 300s); systemd resets the counter when 300s elapses without a burst. **Lesson: `StartLimitBurst` only protects against bursts, not steady-state loops with restart intervals > the window divided by burst count.** For a steady-state cap, raise `RestartSec` enough that the loop counts against the burst budget, or set `Restart=on-failure` + `RestartMaxDelaySec=` to back-off exponentially.
3. **Prefer `Restart=no` while testing a new unit**, then flip to `Restart=on-failure` once you've confirmed the happy path.

Diagnostics:

- `journalctl -u <unit> --since '1 hour ago' --no-pager | grep "Failed with result 'exit-code'"` — count restarts per minute to spot loops.
- `journalctl -b -p err --no-pager | grep -E "timeout|NV_ERR|EMFILE|Too many open files"` — look for system-pressure symptoms in the activation window.
- `systemctl status <unit>` — `Restart counter is at N` field shows how many cycles have happened.

**Trap to avoid:** "the unit is just printing a usage error, that's harmless" — it ISN'T harmless when restarted every 10s for hours. The cumulative system pressure breaks unrelated things.
