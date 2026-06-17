---
name: gotcha-hyprland-lua-migration
description: USE WHEN debugging Hyprland config issues, rolling back to hyprlang, asked about the hyprlang→Lua transition, OR any `hyprctl dispatch <cmd> <args>` call silently no-ops (returns ok or fails with "')' expected near 'X'") — this homelab MIGRATED to Lua on 2026-06-03 (Hyprland 0.55+ deprecated hyprlang, modules/machines/workstation/hyprland.lua is the source). Setting `configType = "lua"` in home-manager stops rendering hyprland.conf entirely. Critical: any `hyprctl dispatch` invocation (from hypridle, scripts, mako handlers, anywhere) must use the `hl.dsp.*` builder form in lua mode — old hyprlang positional syntax silently breaks. Caught twice already: popup-term + DPMS.
---

# Hyprland config language: lua (migrated 2026-06-03)

**Status as of 2026-06-03**: this homelab is on Hyprland 0.55+ via stable nixos-26.05; config is written in Lua at `modules/machines/workstation/hyprland.lua`. `wayland.windowManager.hyprland.configType = "lua"` in `home.nix` makes home-manager stop rendering `hyprland.conf` entirely — Hyprland reads the `.lua` exclusively.

**Migration history** (kept for context):

- Hyprland 0.55 (April 2026) deprecated hyprlang; new format is Lua. Backwards-compat for 1-2 releases then drop.
- 2026-06-03: this homelab migrated to Lua (commit `5775651`).
- Hand-written translation from the home-manager `settings = {...}` tree to `hl.config({...})` / `hl.bind(...)` / `hl.window_rule({...})` calls. The `settings` block was deleted after `configType = "lua"` made it dead code (commit `c834f63`).
- Stylix's hyprland integration follows configType — re-enabled on matched 26.05 versions.

**Rolling back to hyprlang** if needed:

- Revert the commits and rebuild — the runtime `rm hyprland.lua && hyprctl reload` shortcut no longer works because home-manager doesn't render the `.conf` at all when `configType = "lua"`.

## The `hyprctl dispatch` syntax trap (lua mode silently breaks hyprlang invocations)

**The bug.** In lua mode, `hyprctl dispatch <cmd> <args>` wraps as `return hl.dispatch(<cmd> <args>)`. The hyprlang positional form ("dpms off", "workspace 1") becomes a lua syntax error — `')' expected near 'off'` — and the dispatch silently no-ops. Cron/idle/event handlers that *worked perfectly under hyprlang* never fire after the migration.

**The fix.** Use the lua builder form: pass an expression that evaluates to a dispatcher object.

| Hyprlang-style (broken in lua) | Lua-mode form (works) |
|---|---|
| `hyprctl dispatch dpms off` | `hyprctl dispatch 'hl.dsp.dpms("off")'` |
| `hyprctl dispatch dpms on` | `hyprctl dispatch 'hl.dsp.dpms("on")'` |
| `hyprctl dispatch togglespecialworkspace term` | `hyprctl dispatch 'hl.dsp.workspace.toggle_special({ name = "term" })'` |
| `hyprctl dispatch exec ghostty` | `hyprctl dispatch 'hl.dsp.exec_cmd("ghostty")'` |

**Caught instances** (will keep growing — grep before assuming clean):

| When | Site | Symptom |
|---|---|---|
| 2026-06-07 | `popup-term` script (`modules/machines/workstation/home.nix`) | SUPER+RETURN did nothing; only "ok" exit code surfaced the silent fail |
| 2026-06-07 | hypridle DPMS off (`modules/home/desktop/hypr-lock.nix`) | Monitors stayed lit at lock screen since the lua migration; power draw never dropped. Electricity-bill investigation surfaced this |

**Detection commands** (run when in doubt about a dispatch):

```bash
# All hyprctl dispatch call sites in the repo:
grep -rn "hyprctl dispatch" --include='*.nix' --include='*.lua' --include='*.sh' .

# Test a dispatch interactively (lua mode returns ok on success,
# "')' expected near '<arg>'" on broken syntax):
hyprctl dispatch '<your-call-here>'

# Verify monitor DPMS state after dispatch:
hyprctl monitors -j | jq '.[].dpmsStatus'
```

**Rule of thumb.** If you see `hyprctl dispatch X Y Z` where Y/Z aren't quoted as a lua expression, it's broken. Convert to `hl.dsp.<dispatcher>(<args>)`. The builder names are mostly the dispatcher name with underscores: `dpms`, `exec_cmd`, `workspace.toggle_special`, `togglefloating`, `killactive`, etc. — see https://wiki.hypr.land/Configuring/Dispatchers/ + cross-reference the lua bindings.

**Within-hyprlang change worth knowing about** (in case of historical conf files): `windowrulev2` was unified into `windowrule` in 0.54. The new keyword takes the v2-style matcher syntax with multiple effects on one line:

```
windowrule = match:class ^(com\.saivert\.pwvucontrol)$, float, size 700 500, center
```

See https://wiki.hypr.land/0.54.0/Configuring/Window-Rules/ for the historical effect/prop list.
