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
            # Boolean effects in 0.54 take an explicit `on` value (the
            # wiki's `[on]` notation; cf. examples like `no_blur on`).
            # `size` takes two width/height integers.
            "match:class ^(com\\.saivert\\.pwvucontrol)$, float on, size 700 500, center on"
          ];

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
