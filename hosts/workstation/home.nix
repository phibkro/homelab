{
  inputs,
  pkgs,
  lib,
  ...
}:
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
    (mkBindApp "B" "zen" "zen (browser)")

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
{
  # home-manager as a NixOS module (per DESIGN.md L355-358) — config flows
  # from this Nix attrset into ~/.config/hypr/hyprland.conf etc. at
  # activation time.
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  home-manager = {
    useGlobalPkgs = true; # use system nixpkgs, don't fork a per-user one
    useUserPackages = true; # install user pkgs to /etc/profiles/per-user
    extraSpecialArgs = { inherit inputs; };

    # Move pre-existing files aside instead of failing the activation when
    # home-manager wants to symlink in a managed copy. Bit us once already:
    # Hyprland writes an autogenerated `~/.config/hypr/hyprland.conf` on
    # first launch if no config exists; if the user logs in before
    # home-manager has activated, the file lands first and HM refuses to
    # clobber. Backed-up file lands at <path>.hm-backup.
    backupFileExtension = "hm-backup";

    users.nori = {
      imports = [ ../../modules/home/core.nix ];

      home.stateVersion = "25.11"; # match host's system.stateVersion
      programs.home-manager.enable = true;

      # Cheatsheet on PATH. Referenced by SUPER+H as `hypr-cheatsheet`
      # (name, not store path) — avoids the cycle where the binding's
      # store path would depend on the cheatsheet text which depends on
      # the bindings.
      #
      # CLI quality-of-life — lazy-lineage TUIs + system stats peers.
      # Per-user (home-manager) rather than systemPackages because
      # they're shell-driven personal tools, not system services.
      # Naturally portable to nori-laptop / nori-macbook when those
      # land (nix-darwin's home-manager integration uses the same
      # `home.packages` shape).
      home.packages = [
        cheatsheet
        pkgs.nvtopPackages.nvidia # GPU monitor (NVIDIA-only build, smaller closure)
        pkgs.ncdu # interactive disk usage browser
        pkgs.bandwhich # per-process / per-connection network throughput
        pkgs.compsize # btrfs actual-on-disk size + compression ratio
        pkgs.doggo # modern dig — friendlier output
        pkgs.lazysql # SQL TUI (Immich pg, Open WebUI sqlite, etc.)
        pkgs.nix-tree # interactive Nix dependency-graph viewer
        pkgs.nvd # diff between NixOS generations
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
        settings = {
          color_theme = "Default";
          theme_background = false;
        };
      };

      programs.fzf.enable = true; # Ctrl-R history, Ctrl-T file picker, **<Tab> hooks
      programs.zoxide.enable = true; # `z <fragment>` jumps to most-used dir match

      # Cursor — bibata-modern-classic at 24px reads well on the 34" 1440p
      # panel (~6.5mm physical). gtk + x11 + hyprcursor.enable = false
      # because bibata doesn't ship the hyprcursor format yet; XCURSOR is
      # the universal fallback Hyprland honors via the `env` directives
      # below. Swap theme by changing `name` + `package`; size by `size`.
      home.pointerCursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Classic";
        size = 24;
        gtk.enable = true;
        x11.enable = true;
      };

      # Dark mode by default. Three layers:
      #   1. GTK theme (Adwaita-dark) — affects GTK 3/4 apps directly
      #   2. Qt theme (adwaita-dark) — affects Qt apps via qt5ct/qt6ct
      #   3. dconf color-scheme (prefer-dark) — modern XDG signal that
      #      apps like zen, ghostty, Bitwarden Electron, Zed read to
      #      pick their dark variants
      gtk = {
        enable = true;
        theme = {
          name = "Adwaita-dark";
          package = pkgs.gnome-themes-extra;
        };
        # GTK4 reads its theme from gsettings/dconf (which we set in
        # `dconf.settings."org/gnome/desktop/interface".gtk-theme`
        # below), not from ~/.config/gtk-4.0/settings.ini. `null`
        # adopts the new home-manager default (no settings.ini write)
        # and silences the legacy-default warning. Visual behavior
        # unchanged: GTK4 apps still pick up Adwaita-dark via dconf.
        gtk4.theme = null;
        iconTheme.name = "Adwaita";
      };
      qt = {
        enable = true;
        platformTheme.name = "adwaita";
        style.name = "adwaita-dark";
      };
      dconf.settings."org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = "Adwaita-dark";
      };

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
          input = {
            kb_layout = "no";
            follow_mouse = 1;
            sensitivity = 0;
          };

          general = {
            gaps_in = 4;
            gaps_out = 8;
            border_size = 2;
            layout = "dwindle";
          };

          decoration = {
            rounding = 4;
          };

          dwindle = {
            pseudotile = true;
            preserve_split = true;
          };

          # Cursor + dark-mode theme propagation — Hyprland exports
          # these to children at startup. Matches home.pointerCursor +
          # home-manager gtk/qt theme settings above.
          env = [
            "XCURSOR_THEME,Bibata-Modern-Classic"
            "XCURSOR_SIZE,24"
            "GTK_THEME,Adwaita-dark"
            "QT_QPA_PLATFORMTHEME,gtk3"
          ];

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

          # Autostart — polkit agent for elevation prompts + ghostty
          # quick-terminal (matches the windowrule above for shape +
          # position). Status bar / notification daemon / hypridle
          # auto-start via systemd-user-service (UWSM activates
          # graphical-session.target so they don't need exec-once).
          exec-once = [
            "systemctl --user start hyprpolkitagent"
            "ghostty"
          ];
        };
      };
    };
  };
}
