-- ~/.config/hypr/hyprland.lua
-- Translated from machines/workstation/home.nix's
-- wayland.windowManager.hyprland.settings tree.
-- Hyprland 0.55+ format. If broken, rm this file and Hyprland falls
-- back to the still-rendered hyprland.conf.

local mod = "SUPER"

-- Named modifier-combo constants — collapses the repeated raw
-- "SUPER + CTRL"/"SUPER + ALT" string concatenation this modifier
-- scheme has already been through two revisions of this session
-- (ALT<->CTRL for workspaces). One variable to change instead of
-- six-plus call sites next time.
local layerMod = mod -- layers (tags): bare SUPER, the higher-frequency surface
local workspaceMod = mod .. " + CTRL" -- workspaces: SUPER+CTRL
local layerCycleMod = mod .. " + ALT" -- layer-cycle: SUPER+ALT (ALT already means "window switching" elsewhere, kept isolated to cycling only)

------------------
---- MONITORS ----
------------------
-- Samsung S34J552 — 34" ultrawide, native 3440x1440 @ 75Hz on DP-3.
hl.monitor({
    output   = "DP-3",
    mode     = "3440x1440@75",
    position = "0x0",
    scale    = 1.0,
})


-----------------------------
---- LOOK / INPUT / WIDGETS--
-----------------------------

hl.config({
    -- Norwegian keymap to mirror modules/machines/base/base.nix.
    -- follow_mouse=0 → click-to-focus. Stops the floating ghostty
    -- quick-terminal from stealing focus on hover.
    input = {
        kb_layout    = "no",
        follow_mouse = 0,
        sensitivity  = 0,
    },

    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 0,  -- no hard border; focus via shadow-as-glow
        layout      = "dwindle",
    },

    decoration = {
        rounding = 12,  -- Material 3 corner-medium, matches waybar
    },

    dwindle = {
        preserve_split = true,
    },
})


-------------------
---- AUTOSTART ----
-------------------
hl.on("hyprland.start", function()
    -- Refresh dbus activation env + bounce hyprland-session.target so
    -- waybar/hypridle/mako pick up DISPLAY/WAYLAND_DISPLAY etc.
    -- NOTE: using bare command name relies on PATH. When this lua is
    -- promoted into home-manager, swap to ${pkgs.dbus}/bin/... so the
    -- nix-store path is pinned (matching the hyprland.conf rendering).
    hl.exec_cmd("dbus-update-activation-environment --systemd DISPLAY HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE && systemctl --user stop hyprland-session.target && systemctl --user start hyprland-session.target")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    -- These two were `exec-once=[workspace 1 silent] zeditor` in hyprlang.
    -- Workspace-1-silent placement isn't expressed inline here; if it
    -- matters, add a window_rule with `workspace = "1 silent"` matching
    -- the zed / zen-beta class. Skipping for now since they tend to
    -- land on ws 1 anyway via dwindle.
    hl.exec_cmd("zeditor")
    hl.exec_cmd("zen-beta")
    -- snappy-switcher daemon — pre-fetches window list + thumbnails so
    -- the alt+tab overlay shows up instantly on first press.
    hl.exec_cmd("snappy-switcher --daemon")
    -- layer-autohide daemon — hides a shown special-workspace tag when
    -- focus moves to a regular workspace. See home.nix for the script.
    hl.exec_cmd("layer-autohide")
end)


---------------------
---- KEYBINDINGS ----
---------------------

-- Programs
-- SUPER+RETURN runs `popup-term` which is a shell script that:
--   (1) spawns a ghostty.scratch into `special:term` workspace if none exists,
--   (2) `togglespecialworkspace term` to show/hide the overlay.
-- The toggle IS the desired drop-down/quake-style overlay. Don't wrap it
-- in `focuswindow` — that bypasses the togglespecialworkspace step and
-- the overlay stops working.
--
-- `toggle_special`'s table-arg form `{ name = "term" }` is silently
-- broken in Hyprland 0.55.4 (toggles the bare unnamed `special:special`
-- instead) — caught 2026-06-30 when popup-term + the tag binds below
-- both stopped revealing anything. Use the positional-string form
-- `toggle_special("term")` instead; verified working. See
-- [[hyprland-lua-mode-dispatcher-syntax]].
hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd("popup-term"))
hl.bind(mod .. " + SPACE",  hl.dsp.exec_cmd("fuzzel"))
hl.bind(mod .. " + B",      hl.dsp.exec_cmd("zen-beta"))
hl.bind(mod .. " + H",      hl.dsp.exec_cmd("hypr-cheatsheet"))
hl.bind(mod .. " + L",      hl.dsp.exec_cmd("pidof hyprlock || hyprlock"))
hl.bind(mod .. " + P",      hl.dsp.exec_cmd("cmd-menu"))
-- Spacer — tiles like a real window (reserves a slot in the layout)
-- but shows nothing; styled translucent+blurred ("glass") via the
-- spacer-glass window_rule below rather than fully invisible, so it's
-- still a real click target. Close it like any window (SUPER+Q) once
-- focused — no native Hyprland primitive reserves empty tile space
-- without a real window backing it (checked: no dwindle/master option
-- does this; `layoutmsg preselect` only biases the *next* window's
-- split direction, doesn't hold a slot open).
-- --confirm-close-surface=false: ghostty defaults this to true, and
-- since `sleep infinity` never exits, SUPER+Q would otherwise hang
-- waiting on a close-confirmation dialog instead of actually closing
-- (found 2026-07-01 debugging why `hl.dsp.window.close()` reported
-- "ok" but the window never disappeared — had to kill the PID
-- directly to confirm this was the cause).
hl.bind(mod .. " + G",      hl.dsp.exec_cmd("ghostty --class=@spacerClass@ --cursor-style-blink=false --confirm-close-surface=false -e sleep infinity"))

-- Window management
hl.bind(mod .. " + Q",         hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())
hl.bind(mod .. " + V",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F",         hl.dsp.window.fullscreen())
hl.bind(mod .. " + S",         hl.dsp.layout("togglesplit"))  -- dwindle
hl.bind(mod .. " + R",         hl.dsp.exec_cmd("tile-ratio"))  -- fuzzel-pick a split ratio

-- Focus movement (vim keys + arrow keys, both ways)
hl.bind(mod .. " + j",     hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + k",     hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))

-- Workspaces 1-9. CTRL-gated — bare SUPER+N is the special-workspace tag
-- toggles below (tags loop, the higher-frequency surface). CTRL
-- disambiguates "workspace" rather than ALT: ALT already means "window
-- switching" in this config (bare ALT+TAB / SUPER+TAB, both below), so
-- reusing it here would stack a second meaning onto an already-loaded
-- key. CTRL is unbound at the compositor level otherwise.
for i = 1, 9 do
    hl.bind(workspaceMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(workspaceMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- App switcher (snappy-switcher). MRU global = ALT+Tab; workspace-local
-- = SUPER+Tab. The --mod flag MUST match the bind's modifier (snappy
-- uses XKB depressed-modifier tracking for dismiss-on-release).
hl.bind("ALT + TAB",   hl.dsp.exec_cmd("snappy-switcher next --mod alt"))
hl.bind("SUPER + TAB", hl.dsp.exec_cmd("snappy-switcher next --workspace --mod super"))

-- Region screenshot → clipboard (no-modifier bind: just the key string,
-- no leading comma like hyprlang uses).
hl.bind("PRINT", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy -t image/png"))

-- Mouse binds — move/resize by dragging
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })


----------------------
---- WINDOW RULES ----
----------------------

-- pwvucontrol — floating audio control
hl.window_rule({
    name  = "pwvucontrol-float",
    match = { class = "^com\\.saivert\\.pwvucontrol$" },
    float = true,
    size  = "1000 500",
    move  = "2420 50",
})

-- ghostty terminal — floating quick-term docked low-center
hl.window_rule({
    name  = "ghostty-float",
    match = { class = "^com\\.mitchellh\\.ghostty$" },
    float = true,
    size  = "1010 220",
    move  = "1180 1150",
})

hl.window_rule({
    name  = "ghostty-scratch-float",
    match = { class = "^com\\.mitchellh\\.ghostty\\.scratch$" },
    float = true,
    size  = "1010 220",
    move  = "1180 1150",
})

-- SUPER+G spacer — stays TILED (no `float`, unlike the rules above —
-- the point is reserving a real slot in the dwindle tree). Translucent
-- + blurred "glass" rather than fully invisible: `decoration.blur` is
-- already enabled globally (Hyprland default, unset in this config —
-- checked live via `hyprctl getoption decoration:blur:enabled`), so
-- opacity < 1 alone is enough to get the frosted-glass look; no
-- separate blur toggle needed. Dimmer when unfocused (0.15 vs 0.25),
-- matching the Material-elevation convention this config already uses
-- elsewhere (rounding = 12 is "Material 3 corner-medium").
hl.window_rule({
    name    = "spacer-glass",
    match   = { class = "^@spacerClassEscaped@$" },
    opacity = "0.25 0.15",
})

----------------------------------------------------------------------
-- Tag-style named workspaces (handrolled, no plugin).
--
-- Six named special workspaces toggleable via bare SUPER+1..6. Each
-- preserves its own window stack; toggling an overlay shows/hides it
-- without disturbing other workspaces.
--
-- Limitation acknowledged: Hyprland's core renders only ONE special
-- workspace overlay at a time (issue hyprwm/Hyprland#2233); toggling a
-- second hides the first. This is the no-dependency 90% — the
-- multiple-visible-simultaneously semantic of DWM tags requires either
-- a Hyprland plugin (hyprtags, security risk) or a userspace daemon
-- (real engineering project).
--
-- Conflicts with existing wiring:
--   * `term` is also used by popup-term (SUPER+RETURN). SUPER+2
--     toggles the SAME special workspace — fine, just two ways into
--     the same overlay. SUPER+RETURN lazy-spawns ghostty if empty,
--     SUPER+2 just toggles visibility (no spawn).
--
-- Cheatsheet integration:
--   These binds are NOT yet in the SUPER+H cheatsheet (sourced from
--   keyBinds in machines/workstation/home.nix). Add there if these
--   stick after a week of use.
----------------------------------------------------------------------

-- Generated from home.nix's `layerTags` (the sole source of the tag
-- list) via pkgs.replaceVars — was hand-typed here AND in layer-cycle's
-- bash array; two copies of the same fact drifting apart is exactly
-- what home.nix's own header comment names as the failure this file's
-- bind-record system already exists to avoid elsewhere.
local tags = {
    @layerTagsLua@
}

for _, t in ipairs(tags) do
    -- Toggle tag visibility (bare SUPER+N — layers are the bare-SUPER
    -- surface, workspaces are SUPER+CTRL, see the workspace loop above).
    -- Routed through `layer-toggle` (home.nix) rather than dispatching
    -- toggle_special directly — it announces the tag via mako when the
    -- toggle results in it being shown. Positional-string arg to
    -- toggle_special inside that script — the `{ name = t.name }` table
    -- form is broken, see the toggle_special note above SUPER+RETURN.
    hl.bind(layerMod .. " + " .. t.key,
            hl.dsp.exec_cmd("layer-toggle " .. t.name))
    -- Move active window into the tag silently (SUPER+SHIFT+N)
    hl.bind(layerMod .. " + SHIFT + " .. t.key,
            hl.dsp.window.move({ workspace = "special:" .. t.name, silent = true }))
end

-- Step through the tags in order (SUPER+ALT+TAB / SUPER+ALT+SHIFT+TAB),
-- wrapping. `layer-cycle` (machines/workstation/home.nix) tracks which
-- tag is currently shown via `hyprctl monitors -j` and jumps to the
-- next/prev one — a plain toggle can't do this since cycling must
-- always land on a *different* tag, not flip the current one off.
hl.bind(layerCycleMod .. " + TAB",         hl.dsp.exec_cmd("layer-cycle next"))
hl.bind(layerCycleMod .. " + SHIFT + TAB", hl.dsp.exec_cmd("layer-cycle prev"))

-- No static per-app -> tag window_rule here on purpose: Hyprland already
-- spawns new windows into whichever special workspace is currently
-- shown (verified empirically 2026-07-01) — a static rule like
-- `class=thunar -> special:files` only fights that default by
-- force-routing regardless of what's focused at launch time. Show a
-- tag first (bare SUPER+N), then launch — the window lands there for
-- free. Launching with no tag shown lands on the current workspace,
-- visible immediately instead of disappearing into a hidden overlay.
