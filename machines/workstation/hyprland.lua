-- ~/.config/hypr/hyprland.lua
-- Translated from machines/workstation/home.nix's
-- wayland.windowManager.hyprland.settings tree.
-- Hyprland 0.55+ format. If broken, rm this file and Hyprland falls
-- back to the still-rendered hyprland.conf.

local mod = "SUPER"

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
    -- Norwegian keymap to mirror modules/common/base.nix.
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
end)


---------------------
---- KEYBINDINGS ----
---------------------

-- Programs
-- SUPER+RETURN focuses the existing scratch ghostty if one is open;
-- only spawns a fresh popup-term when no scratch window exists. Without
-- the focuswindow guard each press spawned a new ghostty.
hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd(
    "hyprctl dispatch focuswindow class:com.mitchellh.ghostty.scratch || popup-term"
))
hl.bind(mod .. " + SPACE",  hl.dsp.exec_cmd("fuzzel"))
hl.bind(mod .. " + B",      hl.dsp.exec_cmd("zen-beta"))
hl.bind(mod .. " + H",      hl.dsp.exec_cmd("hypr-cheatsheet"))
hl.bind(mod .. " + L",      hl.dsp.exec_cmd("pidof hyprlock || hyprlock"))
hl.bind(mod .. " + P",      hl.dsp.exec_cmd("cmd-menu"))

-- Window management
hl.bind(mod .. " + Q",         hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())
hl.bind(mod .. " + V",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F",         hl.dsp.window.fullscreen())
hl.bind(mod .. " + S",         hl.dsp.layout("togglesplit"))  -- dwindle

-- Focus movement (vim keys + arrow keys, both ways)
hl.bind(mod .. " + j",     hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + k",     hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))

-- Workspaces 1-9
for i = 1, 9 do
    hl.bind(mod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Region screenshot → clipboard
hl.bind(", PRINT", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy -t image/png"))

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
