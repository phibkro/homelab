{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  # ---------------------------------------------------------------------
  # Bind data — single source of truth for the Hyprland config + the
  # SUPER+H cheatsheet. Each record:
  #   mod     modifier prefix as Hyprland sees it ("$mod", "$mod SHIFT", "")
  #   key     key name; may be a template with {n} when `range` is set
  #   action  Hyprland dispatcher + arg; may also use {n}
  #   desc    one-line label for the cheatsheet
  #   range   optional { from; to; step? } — record expands to multiple
  #           Hyprland binds (one per integer); cheatsheet shows it as a
  #           single line with `from..to` substituted into the key.
  # ---------------------------------------------------------------------

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
    {
      mod = "$mod";
      key = "RETURN";
      action = "exec, ghostty";
      desc = "ghostty (terminal)";
    }
    {
      mod = "$mod";
      key = "SPACE";
      action = "exec, fuzzel";
      desc = "fuzzel (launcher)";
    }
    {
      mod = "$mod";
      key = "B";
      action = "exec, zen";
      desc = "zen (browser)";
    }

    # Help / session
    {
      mod = "$mod";
      key = "H";
      action = "exec, hypr-cheatsheet";
      desc = "this cheatsheet";
    }
    {
      mod = "$mod";
      key = "L";
      action = "exec, loginctl lock-session";
      desc = "lock screen";
    }

    # Window
    {
      mod = "$mod";
      key = "Q";
      action = "killactive,";
      desc = "close window";
    }
    {
      mod = "$mod SHIFT";
      key = "E";
      action = "exit,";
      desc = "exit Hyprland";
    }
    {
      mod = "$mod";
      key = "V";
      action = "togglefloating,";
      desc = "toggle floating";
    }
    {
      mod = "$mod";
      key = "F";
      action = "fullscreen,";
      desc = "fullscreen";
    }

    # Focus — H/L claimed by cheatsheet/lock; J/K kept for vim down/up;
    # arrows cover all four directions.
    {
      mod = "$mod";
      key = "j";
      action = "movefocus, d";
      desc = "focus down (vim)";
    }
    {
      mod = "$mod";
      key = "k";
      action = "movefocus, u";
      desc = "focus up (vim)";
    }
    {
      mod = "$mod";
      key = "left";
      action = "movefocus, l";
      desc = "focus left";
    }
    {
      mod = "$mod";
      key = "down";
      action = "movefocus, d";
      desc = "focus down";
    }
    {
      mod = "$mod";
      key = "up";
      action = "movefocus, u";
      desc = "focus up";
    }
    {
      mod = "$mod";
      key = "right";
      action = "movefocus, r";
      desc = "focus right";
    }

    # Workspaces — ranged
    {
      mod = "$mod";
      key = "{n}";
      action = "workspace, {n}";
      range = {
        from = 1;
        to = 9;
      };
      desc = "switch to workspace";
    }
    {
      mod = "$mod SHIFT";
      key = "{n}";
      action = "movetoworkspace, {n}";
      range = {
        from = 1;
        to = 9;
      };
      desc = "move window to workspace";
    }

    # Bare-key (no modifier) — leading comma is correct Hyprland syntax.
    {
      mod = "";
      key = "PRINT";
      action = ''exec, grim -g "$(slurp)" - | wl-copy -t image/png'';
      desc = "screenshot region → clipboard";
    }
  ];

  mouseBinds = [
    {
      mod = "$mod";
      key = "mouse:272";
      action = "movewindow";
      desc = "drag-LMB: move window";
    }
    {
      mod = "$mod";
      key = "mouse:273";
      action = "resizewindow";
      desc = "drag-RMB: resize window";
    }
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
      home.stateVersion = "25.11"; # match host's system.stateVersion
      programs.home-manager.enable = true;

      # Cheatsheet on PATH. Referenced by SUPER+H as `hypr-cheatsheet`
      # (name, not store path) — avoids the cycle where the binding's
      # store path would depend on the cheatsheet text which depends on
      # the bindings.
      home.packages = [ cheatsheet ];

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

          # Cursor theme propagation — Hyprland exports these to children
          # at startup. Matches home.pointerCursor above.
          env = [
            "XCURSOR_THEME,Bibata-Modern-Classic"
            "XCURSOR_SIZE,24"
          ];

          # Mod key — SUPER (Windows / Cmd-equivalent).
          "$mod" = "SUPER";

          # Generated from the structured keyBinds / mouseBinds lists at
          # the top of this file. Range records (e.g. workspaces 1..9)
          # expand to one Hyprland bind per integer; the cheatsheet
          # shows the same range as a single line.
          bind = map toHyprlandBind (lib.concatMap expandRange keyBinds);
          bindm = map toHyprlandBind mouseBinds;

          # Autostart — polkit agent for elevation prompts.
          # Wallpaper / status bar / notification daemon are deferred to
          # follow-up commits (waybar, mako, hyprpaper config).
          exec-once = [
            "systemctl --user start hyprpolkitagent"
          ];
        };
      };
    };
  };
}
