{ pkgs, lib, ... }:
let
  # ---------------------------------------------------------------------
  # Bind data — single source of truth for the Hyprland config + the
  # SUPER+H cheatsheet. Records are built via the small constructor set
  # below; each carries:
  #   mod     modifier prefix as Hyprland sees it ("$mod", "$mod SHIFT", "")
  #   key     key name; may be a template with {n} when `range` is set
  #   action  Hyprland dispatcher + arg; may also use {n}
  #   desc    one-line label for the cheatsheet
  #   range   optional { from; to; step? } — record expands to multiple
  #           Hyprland binds (one per integer); cheatsheet shows it as a
  #           single line with `from..to` substituted into the key.
  # ---------------------------------------------------------------------

  # Constructors. mkBind defaults mod to "$mod" via partial application;
  # mkBindMod takes an explicit mod (e.g. "$mod SHIFT" or "" for bare).
  # mkBindApp / mkBindAppMod auto-prefix the action with "exec, ".
  # withRange wraps a single record with a numeric range — see expandRange.
  mkBindMod = mod: key: action: desc: {
    inherit
      mod
      key
      action
      desc
      ;
  };
  mkBind = mkBindMod "$mod";
  mkBindAppMod =
    mod: key: cmd: desc:
    mkBindMod mod key "exec, ${cmd}" desc;
  mkBindApp = mkBindAppMod "$mod";
  withRange =
    from: to: bind:
    bind // { range = { inherit from to; }; };

  # Pretty-print the mod prefix for the cheatsheet.
  # "$mod SHIFT" → "SUPER + SHIFT"; "$mod" → "SUPER"; "" → "".
  prettyMod =
    m:
    if m == "" then
      ""
    else
      lib.replaceStrings
        [
          "$mod"
          " "
        ]
        [
          "SUPER"
          " + "
        ]
        m;

  # Expand a record with `range` into one record per integer in the
  # sequence, substituting {n} in `key` and `action`. Records without
  # `range` pass through unchanged.
  expandRange =
    b:
    if b ? range then
      let
        step = b.range.step or 1;
        count = ((b.range.to - b.range.from) / step) + 1;
        ns = lib.genList (i: b.range.from + i * step) count;
        sub = n: lib.replaceStrings [ "{n}" ] [ (toString n) ];
      in
      map (
        n:
        b
        // {
          key = sub n b.key;
          action = sub n b.action;
        }
      ) ns
    else
      [ b ];

  # `mod, key, action` — Hyprland's bind/bindm value format.
  toHyprlandBind = b: "${b.mod}, ${b.key}, ${b.action}";

  # One cheatsheet line per logical bind (range records render once with
  # `from..to` in the key slot, not N times).
  cheatsheetLine =
    b:
    let
      keyText =
        if b ? range then
          lib.replaceStrings [ "{n}" ] [ "${toString b.range.from}..${toString b.range.to}" ] b.key
        else
          b.key;
      mod = prettyMod b.mod;
      combo = if mod == "" then keyText else "${mod} + ${keyText}";
    in
    "${combo}  →  ${b.desc}";

  keyBinds = [
    # Apps
    (mkBindApp "RETURN" "ghostty" "ghostty (terminal)")
    (mkBindApp "SPACE" "fuzzel" "fuzzel (launcher)")
    (mkBindApp "B" "zen-beta" "zen (browser)")

    # Help / session
    (mkBindApp "H" "hypr-cheatsheet" "this cheatsheet")
    (mkBindApp "L" "loginctl lock-session" "lock screen")

    # Window
    (mkBind "Q" "killactive," "close window")
    (mkBindMod "$mod SHIFT" "E" "exit," "exit Hyprland")
    (mkBind "V" "togglefloating," "toggle floating")
    (mkBind "F" "fullscreen," "fullscreen")

    # Focus — H/L claimed by cheatsheet/lock; J/K kept for vim down/up;
    # arrows cover all four directions.
    (mkBind "j" "movefocus, d" "focus down (vim)")
    (mkBind "k" "movefocus, u" "focus up (vim)")
    (mkBind "left" "movefocus, l" "focus left")
    (mkBind "down" "movefocus, d" "focus down")
    (mkBind "up" "movefocus, u" "focus up")
    (mkBind "right" "movefocus, r" "focus right")

    # Workspaces — ranged
    (withRange 1 9 (mkBind "{n}" "workspace, {n}" "switch to workspace"))
    (withRange 1 9 (mkBindMod "$mod SHIFT" "{n}" "movetoworkspace, {n}" "move window to workspace"))

    # Bare-key (no modifier) — leading comma is correct Hyprland syntax.
    (mkBindAppMod "" "PRINT" ''grim -g "$(slurp)" - | wl-copy -t image/png''
      "screenshot region → clipboard"
    )
  ];

  mouseBinds = [
    (mkBind "mouse:272" "movewindow" "drag-LMB: move window")
    (mkBind "mouse:273" "resizewindow" "drag-RMB: resize window")
  ];

  # Cheatsheet text → /nix/store file → cat'd into fuzzel by the wrapper.
  # File-based to dodge heredoc indentation quirks; also self-documenting
  # (`cat /nix/store/...-hypr-cheatsheet.txt` to see the rendered text).
  cheatsheetText = lib.concatMapStringsSep "\n" cheatsheetLine (keyBinds ++ mouseBinds);
  cheatsheetFile = pkgs.writeText "hypr-cheatsheet.txt" cheatsheetText;

  cheatsheet = pkgs.writeShellScriptBin "hypr-cheatsheet" ''
    cat ${cheatsheetFile} | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "binds: " --width 64 --lines 24 >/dev/null
  '';
in
# Pure home-manager module — workstation user content. The
# home-manager-as-NixOS-module wrapper (`useGlobalPkgs`,
# `useUserPackages`, `extraSpecialArgs`, `backupFileExtension`,
# `users.nori.imports = [ ./home.nix ]`) lives in the sibling
# `default.nix` so this file's shape matches every other
# machines/<n>/home.nix regardless of NixOS-ness.
{
  imports = [ ../core.nix ];

  home.stateVersion = "25.11"; # match host's system.stateVersion
  programs.home-manager.enable = true;

  # Adopt home-manager's 26.05 default: gtk4 reads its theme from
  # dconf/gsettings, not from a settings.ini write — same path Stylix
  # uses, so explicit null is a no-op at runtime and silences the
  # "legacy default because stateVersion < 26.05" eval warning.
  gtk.gtk4.theme = null;

  # Cheatsheet on PATH. Referenced by SUPER+H as `hypr-cheatsheet`
  # (name, not store path) — avoids the cycle where the binding's
  # store path would depend on the cheatsheet text which depends on
  # the bindings.
  home.packages = [
    cheatsheet
    pkgs.claude-code # per-machine, not core.nix (pi doesn't need Node closure)
    pkgs.nvtopPackages.nvidia # GPU monitor (NVIDIA-only build, smaller closure)
    pkgs.ncdu # interactive disk usage browser
    pkgs.bandwhich # per-process / per-connection network throughput
    pkgs.compsize # btrfs actual-on-disk size + compression ratio
    pkgs.doggo # modern dig — friendlier output
    pkgs.lazysql # SQL TUI (Immich pg, Open WebUI sqlite, etc.)
    pkgs.nix-tree # interactive Nix dependency-graph viewer
    pkgs.nvd # diff between NixOS generations
    # home-manager CLI. `programs.home-manager.enable = true` only wires
    # the activation script (used by NixOS-rebuild); the binary itself
    # isn't installed automatically when home-manager runs as a NixOS
    # module. Useful for `home-manager news`, `home-manager generations`,
    # introspection. Don't `home-manager switch` here — use just rebuild.
    pkgs.home-manager
  ];

  # programs.<x>.enable adds shell integration + declarative config
  # in addition to the binary. Use this form when the integration
  # is the value (fzf Ctrl-R, zoxide z command); use plain
  # home.packages when only the binary is needed (above).
  programs.bash.enable = true; # home-manager owns ~/.bashrc — lets fzf/zoxide auto-source

  programs.lazygit = {
    enable = true;
    settings = {
      gui.theme.lightTheme = false;
      git.paging.colorArg = "always";
    };
  };

  programs.btop = {
    enable = true;
    # color_theme + theme_background managed by Stylix (modules/desktop/
    # stylix.nix) via the Material You palette. Set to `default` here
    # would override Stylix; leave unset.
  };

  programs.fzf.enable = true; # Ctrl-R history, Ctrl-T file picker, **<Tab> hooks
  programs.zoxide.enable = true; # `z <fragment>` jumps to most-used dir match

  # Cursor + GTK + Qt + dconf color-scheme are now managed by Stylix
  # (modules/desktop/stylix.nix) — one wallpaper input drives the
  # Material You palette across the whole desktop. Tweak the wallpaper
  # there to restyle everything in lockstep. The cursor stays Bibata
  # at 24px via `stylix.cursor`.
  #
  # Per-target opt-outs at home-manager scope. modules/desktop/
  # hypr-lock.nix already owns hyprlock.settings.background (blur +
  # screenshot capture); Stylix's hyprlock target would collide.
  stylix.targets.hyprlock.enable = false;

  wayland.windowManager.hyprland = {
    enable = true;

    # Use the system Hyprland (programs.hyprland.enable = true above).
    # Without this home-manager would also install a user-scope copy
    # and the two could drift across rebuilds.
    package = null;
    portalPackage = null;

    settings = {
      # Samsung S34J552 — 34" ultrawide, native 3440x1440 @ 75Hz on DP-3.
      # Position 0x0, scale 1.0 (panel is large enough that 1440p reads
      # well at 1:1; bump to 1.25 if text feels small).
      monitor = [ "DP-3,3440x1440@75,0x0,1" ];

      # Norwegian keymap to mirror modules/common/base.nix (console.keyMap).
      # follow_mouse=0 → click-to-focus (sloppy-focus disabled). Hover
      # alone never moves keyboard focus; you have to click a window
      # to interact with it. Matches macOS / Windows default behaviour
      # and stops the floating ghostty quick-terminal from stealing
      # focus when the cursor passes over it.
      input = {
        kb_layout = "no";
        follow_mouse = 0;
        sensitivity = 0;
      };

      general = {
        gaps_in = 4;
        gaps_out = 8;
        # No hard border — focus indication via shadow-as-glow below.
        border_size = 0;
        layout = "dwindle";
      };

      decoration = {
        # Material 3 corner-medium (12dp) — matches waybar's 12px
        # border-radius for a unified bar/window aesthetic.
        rounding = 12;

        # Glow on focused window — replaces the hard 2px border with
        # a softer Material-style elevation cue. Shadow is technically
        # OUTER (Hyprland has no native inner-glow), but with a small
        # soft-edged colored halo it reads as the focused window
        # having "presence" rather than being framed.
        #
        #   range         glow radius in px
        #   render_power  exponent on the falloff curve (higher = harder edge)
        #   color         rgba(rrggbbaa) — base0D (blue) at ~30% alpha,
        #                 matches Stylix material-darker palette
        #   color_inactive fully transparent — no shadow on unfocused
        #   offset        zero offset → glow not directional shadow
        shadow = {
          enabled = true;
          range = 24;
          render_power = 3;
          # mkForce — Stylix's Hyprland integration also sets shadow
          # color (defaults to a dark surface tint); we want the
          # accent-blue glow on focus, so override.
          color = lib.mkForce "rgba(82aaff4d)";
          color_inactive = lib.mkForce "rgba(00000000)";
          offset = "0 0";
          scale = 1.0;
        };
      };

      dwindle = {
        pseudotile = true;
        # preserve_split off (default) — splits are determined
        # dynamically by the focused window's W/H ratio: wider than
        # tall splits side-by-side, taller than wide splits top-and-
        # bottom. Repeated opens halve the longer dimension each time
        # (the A4→A3→A2 feel). Setting preserve_split=true would lock
        # the direction once chosen and break that.
      };

      # Cursor + GTK / Qt theme env vars now exported by Stylix's
      # Hyprland integration (modules/desktop/stylix.nix). No manual
      # `env = [ XCURSOR_*, GTK_THEME, QT_QPA_PLATFORMTHEME ]` here.

      # Mod key — SUPER (Windows / Cmd-equivalent).
      "$mod" = "SUPER";

      # Window rules — opt floating apps out of tiling.
      # pwvucontrol: small dialog-style mixer; tiles awkwardly in
      # the dwindle layout. Float + center + sized to a readable
      # footprint.
      #
      # Uses the unified `windowrule` keyword (current Hyprland 0.54
      # syntax — supersedes both `windowrule` v1 and `windowrulev2`).
      # Format: `match:<prop> <regex>, <effect>[, <effect>...]`.
      # See https://wiki.hypr.land/0.54.0/Configuring/Window-Rules/.
      windowrule = [
        # pwvucontrol — float at the captured live state, rounded
        # to the nearest 10. Top-right of the 3440x1440 panel:
        # x=2420 + width=1000 leaves a 20px gap from the right edge;
        # y=50 keeps it below waybar (28px) with breathing room.
        # `center on` competes with `move`, so it's dropped.
        "match:class ^(com\\.saivert\\.pwvucontrol)$, float on, size 1000 500, move 2420 50"
        # ghostty quick-terminal — bottom center, 100x10 cells
        # (1010x220 px). Position (1180, 1150) leaves ~70px from
        # the bottom edge, near-centered horizontally on 3440-wide.
        # Auto-spawned on session start via exec-once below.
        "match:class ^(com\\.mitchellh\\.ghostty)$, float on, size 1010 220, move 1180 1150"
      ];

      # Generated from the structured keyBinds / mouseBinds lists at
      # the top of this file. Range records (e.g. workspaces 1..9)
      # expand to one Hyprland bind per integer; the cheatsheet
      # shows the same range as a single line.
      bind = map toHyprlandBind (lib.concatMap expandRange keyBinds);
      bindm = map toHyprlandBind mouseBinds;

      # Autostart — polkit agent for elevation prompts + dev session
      # workspace 1 layout (zeditor + zen-beta side-by-side, dwindle
      # splits horizontally on the second window's arrival → zed on
      # the left, zen on the right). The `[workspace 1 silent]`
      # dispatch prefix sends both apps to workspace 1 without
      # switching focus to it during startup.
      #
      # Ghostty no longer auto-spawns — SUPER+RETURN remains the
      # explicit launch path. The pwvucontrol-style floating window
      # rule for ghostty (lines above) still applies if/when invoked.
      #
      # Status bar / notification daemon / hypridle / hyprsunset
      # auto-start via systemd-user-service (UWSM activates
      # graphical-session.target so they don't need exec-once).
      exec-once = [
        "systemctl --user start hyprpolkitagent"
        "[workspace 1 silent] zeditor"
        "[workspace 1 silent] zen-beta"
      ];
    };
  };
}
