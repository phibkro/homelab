{
  config,
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
    (mkBindApp "RETURN" "popup-term" "ghostty (toggle)")
    (mkBindApp "SPACE" "fuzzel" "fuzzel (launcher)")
    (mkBindApp "B" "zen-beta" "zen (browser)")

    # Help / session
    (mkBindApp "H" "hypr-cheatsheet" "this cheatsheet")
    (mkBindApp "L" "pidof hyprlock || hyprlock" "lock screen")
    (mkBindApp "P" "cmd-menu" "command menu (lock / night / power)")

    # Window
    (mkBind "Q" "killactive," "close window")
    (mkBindMod "$mod SHIFT" "E" "exit," "exit Hyprland")
    (mkBind "V" "togglefloating," "toggle floating")
    (mkBind "F" "fullscreen," "fullscreen")
    (mkBind "S" "layoutmsg, togglesplit" "toggle split orientation")

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

  # Command menu — a fuzzel dmenu of system actions (same pattern as the
  # cheatsheet, same Stylix theme). Each entry wraps a tool already in use:
  # lock = hyprlock, night mode = the hyprsunset user unit (mirrors waybar's
  # toggle), reboot/poweroff = systemctl. Destructive actions gate behind a
  # yes/no confirm. Bound to SUPER+ESCAPE.
  cmdMenu = pkgs.writeShellScriptBin "cmd-menu" ''
    fuzzel=${pkgs.fuzzel}/bin/fuzzel
    confirm() { [ "$(printf 'No\nYes\n' | "$fuzzel" --dmenu --prompt "$1 ")" = "Yes" ]; }
    case "$(printf 'Lock\nNight mode\nReboot\nPower off\n' | "$fuzzel" --dmenu --prompt "cmd: ")" in
      "Lock")       pidof hyprlock || hyprlock ;;
      "Night mode") systemctl --user is-active --quiet hyprsunset && systemctl --user stop hyprsunset || systemctl --user start hyprsunset ;;
      "Reboot")     confirm "Reboot?"    && systemctl reboot ;;
      "Power off")  confirm "Power off?" && systemctl poweroff ;;
    esac
  '';

  # SUPER+RETURN terminal — togglable/ephemeral, a special-workspace
  # scratchpad. Lazy-spawn the ghostty (its own class so it's detectable and
  # the default-ghostty float rule doesn't catch it) on first press if it
  # isn't already running, then toggle show/hide. Lazy beats an exec-once
  # pre-spawn: survives `hyprctl reload`, needs no relogin, no startup race.
  popupTerm = pkgs.writeShellScriptBin "popup-term" ''
    if ! hyprctl clients | grep -q "com.mitchellh.ghostty.scratch"; then
      hyprctl dispatch exec "[workspace special:term silent] ghostty --class=com.mitchellh.ghostty.scratch"
    fi
    hyprctl dispatch togglespecialworkspace term
  '';
in
# Pure home-manager module — workstation user content. The
# home-manager-as-NixOS-module wrapper (`useGlobalPkgs`,
# `useUserPackages`, `extraSpecialArgs`, `backupFileExtension`,
# `users.nori.imports = [ ./home.nix ]`) lives in the sibling
# `default.nix` so this file's shape matches every other
# machines/<n>/home.nix regardless of NixOS-ness.
{
  imports = [ ../pc.nix ];

  home.stateVersion = "25.11"; # match host's system.stateVersion
  programs.home-manager.enable = true;

  # Cheatsheet on PATH. Referenced by SUPER+H as `hypr-cheatsheet`
  # (name, not store path) — avoids the cycle where the binding's
  # store path would depend on the cheatsheet text which depends on
  # the bindings.
  home.packages = [
    cheatsheet
    cmdMenu # SUPER+ESCAPE command menu (lock / night mode / reboot / power off)
    popupTerm # SUPER+RETURN togglable terminal (lazy-spawns its own ghostty)
    pkgs.gh # GitHub CLI — PR ops, gh auth, gh api …
    pkgs.nvtopPackages.nvidia # GPU monitor (NVIDIA-only build, smaller closure)
    pkgs.ncdu # interactive disk usage browser
    pkgs.bandwhich # per-process / per-connection network throughput
    pkgs.compsize # btrfs actual-on-disk size + compression ratio
    pkgs.doggo # modern dig — friendlier output
    pkgs.lazysql # SQL TUI (Immich pg, Open WebUI sqlite, etc.)
    pkgs.nix-tree # interactive Nix dependency-graph viewer
    pkgs.nvd # diff between NixOS generations
    pkgs.handbrake # GUI video transcoder (GTK). Mac counterpart is a brew cask — broken on x86_64-darwin in nixpkgs; see machines/macbook/home.nix.
    pkgs.deno # TS/JS runtime + the security sandbox for `pagu` (the local
    # capability-gated agent in the gitignored ./pagu repo). pagu runs on
    # Deno and its permission model IS pagu's sandbox, so deno must be on
    # PATH; `~/.deno/bin` (deno install targets) is added to PATH below.
    pkgs.bubblewrap # pagu's OS sandbox tier: when `bwrap` is on PATH, the
    # runner wraps each script in a kernel-level wall beneath Deno's perms
    # (denies network, confines writes — contains even --allow-run
    # subprocesses, which Deno doesn't bound). Optional; pagu falls back to
    # the Deno-permission floor without it.
    # home-manager CLI. `programs.home-manager.enable = true` only wires
    # the activation script (used by NixOS-rebuild); the binary itself
    # isn't installed automatically when home-manager runs as a NixOS
    # module. Useful for `home-manager news`, `home-manager generations`,
    # introspection. Don't `home-manager switch` here — use just rebuild.
    pkgs.home-manager
  ];

  # `deno install -g` drops shims here (e.g. the `pagu` command); put it on
  # PATH so they're runnable from a bare shell.
  home.sessionPath = [ "$HOME/.deno/bin" ];

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

  # ~/nori + the standard working folders are out-of-store symlinks into the
  # @srv-nori subvolume (networked over Samba + own backup tier). Canonical
  # data lives on /srv/nori; apps use the normal home paths; Samba serves the
  # real dirs natively (no follow-symlink needed). This is the allowlist shape:
  # only these harmless working dirs are relocated onto the share — secrets
  # (~/.ssh, ~/.config/sops, ~/.claude.json) stay on @home and never enter the
  # shared tree, so there's nothing to filter out. /srv/nori only exists on
  # workstation, so this lives here, not in the cross-machine core.nix.
  home.file =
    let
      link = target: {
        source = config.lib.file.mkOutOfStoreSymlink target;
      };
    in
    {
      "nori" = link "/srv/nori";
      "Documents" = link "/srv/nori/Documents";
      "Videos" = link "/srv/nori/Videos";
      "Photos" = link "/srv/nori/Photos";
      "Downloads" = link "/srv/nori/Downloads";
      "Desktop" = link "/srv/nori/Desktop";
      "Projects" = link "/srv/nori/Projects";
    };

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

    # Hyprland 0.55+ hyprlang-vs-lua selector. We use lua via
    # xdg.configFile."hypr/hyprland.lua" at the bottom of this file.
    # The conf-side `settings = {...}` block below still renders
    # hyprland.conf as a fallback (Hyprland prefers .lua when present),
    # so `rm ~/.config/hypr/hyprland.lua && hyprctl reload` is a clean
    # runtime rollback to hyprlang. Also silences the home-manager
    # release-26.05 eval warning about the default flipping from
    # "hyprlang" to "lua" at home.stateVersion ≥ 26.05.
    configType = "lua";
  };

  # Hyprland 0.55+ Lua config. With `configType = "lua"` above,
  # home-manager stops rendering hyprland.conf — Hyprland reads this
  # `.lua` exclusively. Rollback now means revert + rebuild (the
  # runtime `rm hyprland.lua + hyprctl reload` shortcut documented in
  # the lua-migration commit no longer applies).
  xdg.configFile."hypr/hyprland.lua".source = ./hyprland.lua;
}
