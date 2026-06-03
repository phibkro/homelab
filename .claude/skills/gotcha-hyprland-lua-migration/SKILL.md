---
name: gotcha-hyprland-lua-migration
description: USE WHEN debugging Hyprland config issues, rolling back to hyprlang, or asked about the hyprlang→Lua transition — this homelab MIGRATED to Lua on 2026-06-03 (Hyprland 0.55+ deprecated hyprlang, machines/workstation/hyprland.lua is the source). Setting `configType = "lua"` in home-manager stops rendering hyprland.conf entirely.
---

# Hyprland config language: lua (migrated 2026-06-03)

**Status as of 2026-06-03**: this homelab is on Hyprland 0.55+ via stable nixos-26.05; config is written in Lua at `machines/workstation/hyprland.lua`. `wayland.windowManager.hyprland.configType = "lua"` in `home.nix` makes home-manager stop rendering `hyprland.conf` entirely — Hyprland reads the `.lua` exclusively.

**Migration history** (kept for context):

- Hyprland 0.55 (April 2026) deprecated hyprlang; new format is Lua. Backwards-compat for 1-2 releases then drop.
- 2026-06-03: this homelab migrated to Lua (commit `5775651`).
- Hand-written translation from the home-manager `settings = {...}` tree to `hl.config({...})` / `hl.bind(...)` / `hl.window_rule({...})` calls. The `settings` block was deleted after `configType = "lua"` made it dead code (commit `c834f63`).
- Stylix's hyprland integration follows configType — re-enabled on matched 26.05 versions.

**Rolling back to hyprlang** if needed:

- Revert the commits and rebuild — the runtime `rm hyprland.lua && hyprctl reload` shortcut no longer works because home-manager doesn't render the `.conf` at all when `configType = "lua"`.

**Within-hyprlang change worth knowing about** (in case of historical conf files): `windowrulev2` was unified into `windowrule` in 0.54. The new keyword takes the v2-style matcher syntax with multiple effects on one line:

```
windowrule = match:class ^(com\.saivert\.pwvucontrol)$, float, size 700 500, center
```

See https://wiki.hypr.land/0.54.0/Configuring/Window-Rules/ for the historical effect/prop list.
