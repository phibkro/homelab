{
  config,
  pkgs,
  lib,
  ...
}:
let
  nativeLayout = "dwindle";
  gapsOut = 8;
  layoutCore = ./layout.lua;
  riceAdapter = ./rice.lua;

  /*
    ---------------------------------------------------------------------
    Bind data — single source of truth for the palette cheatsheet.
    riceCommandBindings additionally generate their Hyprland Lua lines,
    so the spacer/ratio/layout command mapping cannot drift. Records are
    built via the small constructor set below; each carries:
      mod     modifier prefix as Hyprland sees it ("$mod", "$mod SHIFT", "")
      key     key name; may be a template with {n} when `range` is set
      action  Hyprland dispatcher + arg; may also use {n}
      desc    one-line label for the cheatsheet
      range   optional { from; to; step? } — record expands to multiple
              Hyprland binds (one per integer); cheatsheet shows it as a
              single line with `from..to` substituted into the key.
    ---------------------------------------------------------------------
  */

  /*
    Constructors. mkBind defaults mod to "$mod" via partial application;
    mkBindMod takes an explicit mod (e.g. "$mod SHIFT" or "" for bare).
    mkBindApp / mkBindAppMod auto-prefix the action with "exec, ".
    withRange wraps a single record with a numeric range — see expandRange.
  */
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

  mkCommand =
    attrs:
    {
      description = attrs.label;
      keywords = [ ];
      icon = "system-run";
      effect = "launch";
      palette = true;
      directBinding = null;
      args = [ ];
    }
    // attrs;

  baseCommands = {
    "layout.menu" = mkCommand {
      label = "Layout: Workspace Menu…";
      description = "workspace layout menu";
      category = "layout";
      executable = "${hyprLayoutMenu}/bin/hypr-layout-menu";
      args = [ "menu" ];
      palette = false;
      directBinding = {
        mod = "$mod SHIFT";
        key = "R";
      };
    };
    "layout.presets" = mkCommand {
      label = "Layout: Presets…";
      description = "choose a workspace layout preset";
      category = "layout";
      executable = "${hyprLayoutMenu}/bin/hypr-layout-menu";
      args = [ "presets" ];
      keywords = [ "grid" ];
      icon = "view-grid-symbolic";
      effect = "layout";
    };
    "layout.custom" = mkCommand {
      label = "Layout: Custom…";
      description = "enter a workspace layout expression";
      category = "layout";
      executable = "${hyprLayoutMenu}/bin/hypr-layout-menu";
      args = [ "custom" ];
      keywords = [ "grid" ];
      icon = "view-grid-symbolic";
      effect = "layout";
    };
    "layout.reset" = mkCommand {
      label = "Layout: Reset";
      description = "return the workspace to Dwindle";
      category = "layout";
      executable = "${hyprLayout}/bin/hypr-layout";
      args = [ "reset" ];
      keywords = [ "dwindle" ];
      icon = "view-restore-symbolic";
      effect = "layout";
    };
    "layout.ratio" = mkCommand {
      label = "Layout: Focused Window Ratio…";
      description = "focused window ratio";
      category = "layout";
      executable = "${tileRatio}/bin/tile-ratio";
      keywords = [
        "resize"
        "fraction"
        "percent"
      ];
      icon = "view-split-left-right-symbolic";
      effect = "layout";
      directBinding = {
        mod = "$mod";
        key = "R";
      };
    };

    "space.popup-terminal" = mkCommand {
      label = "Space: Toggle Popup Terminal";
      description = "ghostty popup terminal";
      category = "space";
      executable = "${popupTerm}/bin/popup-term";
      keywords = [
        "scratchpad"
        "term"
      ];
      icon = "utilities-terminal-symbolic";
      effect = "toggle";
    };
    "space.persona-search" = mkCommand {
      label = "Space: Persona App Search";
      description = "toggle the Persona application search";
      category = "space";
      executable = "${pkgs.quickshell}/bin/qs";
      args = [
        "-c"
        "persona"
        "ipc"
        "call"
        "searchapp"
        "toggle"
      ];
      keywords = [
        "applications"
        "launcher"
        "search"
      ];
      icon = "system-search-symbolic";
      effect = "toggle";
    };
    "space.cycle.next" = mkCommand {
      label = "Space: Cycle Next";
      description = "show the next special space";
      category = "space";
      executable = "${layerCycle}/bin/layer-cycle";
      args = [ "next" ];
      effect = "toggle";
    };
    "space.cycle.previous" = mkCommand {
      label = "Space: Cycle Previous";
      description = "show the previous special space";
      category = "space";
      executable = "${layerCycle}/bin/layer-cycle";
      args = [ "prev" ];
      effect = "toggle";
    };

    "window.close" = mkCommand {
      label = "Window: Close Focused";
      description = "close the focused window";
      category = "window";
      executable = "${pkgs.hyprland}/bin/hyprctl";
      args = [
        "dispatch"
        "hl.dsp.window.close()"
      ];
      icon = "window-close-symbolic";
      effect = "window";
    };
    "window.fullscreen" = mkCommand {
      label = "Window: Toggle Fullscreen";
      description = "toggle fullscreen for the focused window";
      category = "window";
      executable = "${pkgs.hyprland}/bin/hyprctl";
      args = [
        "dispatch"
        "hl.dsp.window.fullscreen()"
      ];
      effect = "window";
    };
    "window.float" = mkCommand {
      label = "Window: Toggle Floating";
      description = "toggle floating for the focused window";
      category = "window";
      executable = "${pkgs.hyprland}/bin/hyprctl";
      args = [
        "dispatch"
        ''hl.dsp.window.float({ action = "toggle" })''
      ];
      effect = "window";
    };
    "window.split" = mkCommand {
      label = "Window: Toggle Split Direction";
      description = "toggle Dwindle split direction";
      category = "window";
      executable = "${pkgs.hyprland}/bin/hyprctl";
      args = [
        "dispatch"
        ''hl.dsp.layout("togglesplit")''
      ];
      effect = "window";
    };
    "window.focus.left" = mkCommand {
      label = "Window: Focus Left";
      description = "focus the window to the left";
      category = "window";
      executable = "${pkgs.hyprland}/bin/hyprctl";
      args = [
        "dispatch"
        ''hl.dsp.focus({ direction = "left" })''
      ];
      effect = "window";
    };
    "window.focus.right" = mkCommand {
      label = "Window: Focus Right";
      description = "focus the window to the right";
      category = "window";
      executable = "${pkgs.hyprland}/bin/hyprctl";
      args = [
        "dispatch"
        ''hl.dsp.focus({ direction = "right" })''
      ];
      effect = "window";
    };
    "window.focus.up" = mkCommand {
      label = "Window: Focus Up";
      description = "focus the window above";
      category = "window";
      executable = "${pkgs.hyprland}/bin/hyprctl";
      args = [
        "dispatch"
        ''hl.dsp.focus({ direction = "up" })''
      ];
      effect = "window";
    };
    "window.focus.down" = mkCommand {
      label = "Window: Focus Down";
      description = "focus the window below";
      category = "window";
      executable = "${pkgs.hyprland}/bin/hyprctl";
      args = [
        "dispatch"
        ''hl.dsp.focus({ direction = "down" })''
      ];
      effect = "window";
    };

    "system.lock" = mkCommand {
      label = "System: Lock";
      description = "lock screen";
      category = "system";
      executable = "${lockScreen}/bin/lock-screen";
      keywords = [ "hyprlock" ];
      icon = "system-lock-screen-symbolic";
      directBinding = {
        mod = "$mod";
        key = "L";
      };
    };
    "system.night-mode" = mkCommand {
      label = "System: Toggle Night Mode";
      description = "toggle Hyprsunset";
      category = "system";
      executable = "${nightMode}/bin/toggle-night-mode";
      keywords = [
        "hyprsunset"
        "warm"
      ];
      icon = "weather-clear-night-symbolic";
      effect = "toggle";
    };
    "system.reboot" = mkCommand {
      label = "System: Reboot…";
      description = "reboot the machine";
      category = "system";
      executable = "${pkgs.systemd}/bin/systemctl";
      args = [ "reboot" ];
      keywords = [ "restart" ];
      icon = "system-reboot-symbolic";
      effect = "destructive";
    };
    "system.poweroff" = mkCommand {
      label = "System: Power Off…";
      description = "power off the machine";
      category = "system";
      executable = "${pkgs.systemd}/bin/systemctl";
      args = [ "poweroff" ];
      keywords = [ "shutdown" ];
      icon = "system-shutdown-symbolic";
      effect = "destructive";
    };
    "session.exit" = mkCommand {
      label = "Session: Exit Hyprland…";
      description = "exit the Hyprland desktop session";
      category = "session";
      executable = "${pkgs.hyprland}/bin/hyprctl";
      args = [
        "dispatch"
        "hl.dsp.exit()"
      ];
      keywords = [
        "quit"
        "logout"
      ];
      icon = "system-log-out-symbolic";
      effect = "destructive";
    };

    "help.shortcuts" = mkCommand {
      label = "Help: Keyboard Shortcuts";
      description = "show the keyboard shortcut cheatsheet";
      category = "help";
      executable = "hypr-cheatsheet";
      keywords = [
        "bindings"
        "keys"
      ];
      icon = "preferences-desktop-keyboard-shortcuts-symbolic";
      effect = "query";
    };

    "utility.glass-spacer" = mkCommand {
      label = "Utility: Glass Spacer";
      description = "glass spacer";
      category = "utility";
      executable = "${glassSpacer}/bin/glass-spacer";
      keywords = [
        "empty"
        "tile"
      ];
      icon = "window-new-symbolic";
      directBinding = {
        mod = "$mod";
        key = "G";
      };
    };
    "utility.screenshot-region" = mkCommand {
      label = "Utility: Screenshot Region";
      description = "copy a selected region to the clipboard";
      category = "utility";
      executable = "${regionScreenshot}/bin/screenshot-region";
      keywords = [
        "grim"
        "slurp"
        "clipboard"
      ];
      icon = "applets-screenshooter-symbolic";
    };

    "view.frequent" = mkCommand {
      label = "View: Frequent";
      description = "reopen the default relevance-ranked palette";
      category = "view";
      executable = "rice-palette";
      args = [ "frequent" ];
      icon = "document-open-recent-symbolic";
      effect = "query";
    };
    "view.alphabetical" = mkCommand {
      label = "View: Alphabetical";
      description = "reopen the title-ordered palette";
      category = "view";
      executable = "rice-palette";
      args = [ "alphabetical" ];
      icon = "view-sort-ascending-symbolic";
      effect = "query";
    };
    "view.categories" = mkCommand {
      label = "View: Browse Categories…";
      description = "choose a command category";
      category = "view";
      executable = "rice-palette";
      args = [ "categories" ];
      icon = "view-list-symbolic";
      effect = "query";
    };
  };

  layerCommands = builtins.listToAttrs (
    map (
      tag:
      lib.nameValuePair "space.toggle.${tag.name}" (mkCommand {
        label = "Space: Toggle ${tag.name}";
        description = "toggle the ${tag.name} special space";
        category = "space";
        executable = "${layerToggle}/bin/layer-toggle";
        args = [ tag.name ];
        keywords = [
          tag.name
          "special workspace"
        ];
        icon = "view-paged-symbolic";
        effect = "toggle";
      })
    ) layerTags
  );

  commandCategories = [
    "layout"
    "space"
    "window"
    "system"
    "session"
    "help"
    "view"
    "utility"
  ];
  commandEffects = [
    "launch"
    "query"
    "toggle"
    "layout"
    "window"
    "session"
    "destructive"
  ];
  directBindingType = lib.types.submodule {
    options = {
      mod = lib.mkOption {
        type = lib.types.enum [
          "$mod"
          "$mod SHIFT"
        ];
      };
      key = lib.mkOption { type = lib.types.str; };
    };
  };
  commandType = lib.types.submodule {
    options = {
      label = lib.mkOption { type = lib.types.str; };
      description = lib.mkOption { type = lib.types.str; };
      category = lib.mkOption { type = lib.types.enum commandCategories; };
      keywords = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      icon = lib.mkOption {
        type = lib.types.str;
        default = "system-run";
      };
      executable = lib.mkOption { type = lib.types.str; };
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      effect = lib.mkOption {
        type = lib.types.enum commandEffects;
        default = "launch";
      };
      palette = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      directBinding = lib.mkOption {
        type = lib.types.nullOr directBindingType;
        default = null;
      };
    };
  };
  commandRegistry = lib.evalModules {
    modules = [
      {
        options.commands = lib.mkOption {
          type = lib.types.attrsOf commandType;
        };
        config.commands = baseCommands // layerCommands;
      }
    ];
  };
  validCommandId = id: builtins.match "^[a-z0-9]+([.-][a-z0-9]+)*$" id != null;
  validatedCommands =
    assert lib.assertMsg (lib.all validCommandId (
      builtins.attrNames commandRegistry.config.commands
    )) "invalid rice command ID";
    assert lib.assertMsg (lib.all
      (command: command.effect != "destructive" || command.directBinding == null)
      (builtins.attrValues commandRegistry.config.commands)
    ) "destructive rice commands cannot have direct bindings";
    commandRegistry.config.commands;

  riceCommandBindings = lib.mapAttrsToList (
    id: command:
    command.directBinding
    // {
      inherit id;
      command = "rice-command ${id}";
      desc = command.description;
    }
  ) (lib.filterAttrs (_: command: command.directBinding != null) validatedCommands);

  riceCommandKeyBinds = map (
    bind: mkBindAppMod bind.mod bind.key bind.command bind.desc
  ) riceCommandBindings;

  riceCommandBindsLua = lib.concatMapStringsSep "\n" (
    bind:
    let
      combo =
        if bind.mod == "$mod SHIFT" then
          ''mod .. " + SHIFT + ${bind.key}"''
        else if bind.mod == "$mod" then
          ''mod .. " + ${bind.key}"''
        else
          throw "unsupported generated rice command modifier: ${bind.mod}";
    in
    "hl.bind(${combo}, hl.dsp.exec_cmd(${builtins.toJSON bind.command}))"
  ) riceCommandBindings;

  keyBinds = [
    # Apps
    (mkBindApp "RETURN" "popup-term" "ghostty (toggle)")
    (mkBindApp "SPACE" "rice-palette" "applications and commands")
    (mkBindApp "B" "zen-beta" "zen (browser)")

    # Window
    (mkBind "Q" "killactive," "close window")
    (mkBind "V" "togglefloating," "toggle floating")
    (mkBind "F" "fullscreen," "fullscreen")
    (mkBind "S" "layoutmsg, togglesplit" "toggle split orientation")
  ]
  ++ riceCommandKeyBinds
  ++ [
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

  # File-based (not heredoc) to dodge shell-quoting quirks at the
  # fuzzel call site below.
  cheatsheetText = lib.concatMapStringsSep "\n" cheatsheetLine (keyBinds ++ mouseBinds);
  cheatsheetFile = pkgs.writeText "hypr-cheatsheet.txt" cheatsheetText;

  cheatsheet = pkgs.writeShellApplication {
    name = "hypr-cheatsheet";
    runtimeInputs = [ pkgs.fuzzel ];
    text = ''
      fuzzel --dmenu --prompt 'binds: ' --width 64 --lines 24 <${cheatsheetFile} >/dev/null
    '';
  };

  lockScreen = pkgs.writeShellApplication {
    name = "lock-screen";
    runtimeInputs = [
      pkgs.hyprlock
      pkgs.procps
    ];
    text = ''
      if ! pidof hyprlock >/dev/null; then
        exec hyprlock
      fi
    '';
  };

  nightMode = pkgs.writeShellApplication {
    name = "toggle-night-mode";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if systemctl --user is-active --quiet hyprsunset; then
        systemctl --user stop hyprsunset
      else
        systemctl --user start hyprsunset
      fi
    '';
  };

  regionScreenshot = pkgs.writeShellApplication {
    name = "screenshot-region";
    runtimeInputs = [
      pkgs.grim
      pkgs.slurp
      pkgs.wl-clipboard
    ];
    text = ''
      set +e
      geometry=$(slurp)
      status=$?
      set -e
      [[ $status -eq 1 ]] && exit 0
      [[ $status -eq 0 ]] || exit "$status"
      [[ -n $geometry ]] || exit 0
      grim -g "$geometry" - | wl-copy -t image/png
    '';
  };

  riceCommandCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      id: command:
      let
        invocation = lib.escapeShellArgs ([ command.executable ] ++ command.args);
      in
      if command.effect == "destructive" then
        ''
          ${lib.escapeShellArg id})
            if confirm_command ${lib.escapeShellArg command.label}; then
              run_command ${invocation}
            else
              status=$?
              [[ $status -eq 1 ]] && exit 0
              exit "$status"
            fi
            ;;
        ''
      else
        ''
          ${lib.escapeShellArg id})
            run_command ${invocation}
            ;;
        ''
    ) validatedCommands
  );

  riceCommand = pkgs.writeShellApplication {
    name = "rice-command";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.fuzzel
      pkgs.libnotify
    ];
    text = ''
      if [[ $# -ne 1 ]]; then
        printf 'usage: rice-command COMMAND_ID\n' >&2
        exit 64
      fi

      fuzzel_bin=''${FUZZEL_BIN:-fuzzel}
      notify_send_bin=''${NOTIFY_SEND_BIN:-notify-send}

      run_command() {
        local error_file status body
        error_file=$(mktemp)
        set +e
        "$@" 2> >(tee "$error_file" >&2)
        status=$?
        set -e
        if [[ $status -ne 0 ]]; then
          body=$(<"$error_file")
          "$notify_send_bin" -a rice-command 'Command failed' "''${body:-$1 exited with status $status}" || true
        fi
        rm -f "$error_file"
        return "$status"
      }

      confirm_command() {
        local label=$1 choice status
        set +e
        choice=$(printf 'No\nYes\n' | "$fuzzel_bin" --dmenu --only-match --index --prompt "$label ")
        status=$?
        set -e
        [[ $status -eq 1 ]] && return 1
        [[ $status -eq 0 ]] || return "$status"
        case $choice in
          0) return 1 ;;
          1) return 0 ;;
          *)
            printf 'rice-command: invalid confirmation result: %s\n' "$choice" >&2
            return 64
            ;;
        esac
      }

      case $1 in
        ${riceCommandCases}
        *)
          printf 'rice-command: unknown command ID: %s\n' "$1" >&2
          exit 64
          ;;
      esac
    '';
  };

  commandManifestPackage = pkgs.writeTextDir "share/rice/commands.json" (
    builtins.toJSON (
      lib.mapAttrs (_: command: {
        inherit (command)
          category
          directBinding
          effect
          palette
          ;
      }) validatedCommands
    )
  );

  privateDesktopItems = lib.mapAttrsToList (
    id:
    command@{ keywords, ... }:
    pkgs.makeDesktopItem {
      name = "nori-rice-${id}";
      desktopName = command.label;
      genericName = command.description;
      exec = "${riceCommand}/bin/rice-command ${id}";
      inherit (command) icon;
      inherit keywords;
    }
  ) (lib.filterAttrs (_: command: command.palette) validatedCommands);

  privateDesktopEntries = pkgs.symlinkJoin {
    name = "rice-private-applications";
    paths = privateDesktopItems ++ [ commandManifestPackage ];
  };

  riceLaunch = pkgs.writeShellApplication {
    name = "rice-launch";
    text = builtins.readFile ./rice-launch.sh;
  };

  ricePalette = pkgs.writeShellApplication {
    name = "rice-palette";
    runtimeInputs = [ pkgs.fuzzel ];
    text = ''
      export RICE_PRIVATE_DATA_DIR=${lib.escapeShellArg "${privateDesktopEntries}/share"}
      export RICE_LAUNCH_PREFIX_BIN=${lib.escapeShellArg "${riceLaunch}/bin/rice-launch"}
      ${builtins.readFile ./rice-palette.sh}
    '';
  };

  hyprPaletteLiveTest = pkgs.writeShellApplication {
    name = "hypr-palette-live-test";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.sway
      pkgs.gnugrep
      pkgs.wtype
      ricePalette
    ];
    text = builtins.readFile ./hypr-palette-live-test.sh;
  };

  glassSpacer = pkgs.writeShellApplication {
    name = "glass-spacer";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.ghostty
    ];
    text = ''
      exec ghostty --class=${lib.escapeShellArg spacerClass} --cursor-style-blink=false --confirm-close-surface=false -e sleep infinity
    '';
  };

  tileRatio = pkgs.writeShellApplication {
    name = "tile-ratio";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.fuzzel
      pkgs.gawk
      pkgs.hyprland
      pkgs.jq
    ];
    text = ''
      export TILE_RATIO_GAPS_OUT=${toString gapsOut}
      ${builtins.readFile ./tile-ratio.sh}
    '';
  };

  hyprLayout = pkgs.writeShellApplication {
    name = "hypr-layout";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
    ];
    text = builtins.readFile ./hypr-layout.sh;
  };

  hyprLayoutMenu = pkgs.writeShellApplication {
    name = "hypr-layout-menu";
    runtimeInputs = [
      pkgs.fuzzel
      hyprLayout
    ];
    text = builtins.readFile ./hypr-layout-menu.sh;
  };

  /*
    hypr-session — event-log capture + tmux-style restore. Packaging
    lives in its own subdirectory (modules/home/desktop/hypr-rice/
    hypr-session/default.nix) because it bundles four scripts into one
    colocated $out/bin rather than fitting the one-writeShellApplication-
    per-script pattern the rest of this file uses — see that file's
    header comment for why. Design doc:
    docs/specs/2026-07-20-hypr-session-persistence-design.md
  */
  hyprSession = pkgs.callPackage ./hypr-session { };

  hyprLayoutLiveTest = pkgs.writeShellApplication {
    name = "hypr-layout-live-test";
    excludeShellChecks = [ "SC2016" ];
    runtimeInputs = [
      glassSpacer
      hyprLayout
      pkgs.coreutils
      pkgs.ghostty
      pkgs.hyprland
      pkgs.jq
      tileRatio
    ];
    text = ''
      export HYPR_RICE_SPACER_CLASS=${lib.escapeShellArg spacerClass}
      ${builtins.readFile ./hypr-layout-live-test.sh}
    '';
  };

  /*
    SUPER+RETURN terminal — togglable/ephemeral, a special-workspace
    scratchpad. Lazy-spawn the ghostty (its own class so it's detectable and
    the default-ghostty float rule doesn't catch it) on first press if it
    isn't already running, then toggle show/hide. Lazy beats an exec-once
    pre-spawn: survives `hyprctl reload`, needs no relogin, no startup race.
    Hyprland lua-mode (`configType = "lua"` below) changed the
    `hyprctl dispatch` CLI: it now wraps args in `return hl.dispatch(...)`,
    so the old hyprlang-style `dispatch togglespecialworkspace term`
    syntax silently fails with "')' expected near 'term'". Same for
    `dispatch exec`. Fix: pass a lua dispatcher builder as the arg.
    Caught 2026-06-07 — popup-term had been broken since the lua
    migration but the failure mode is silent (exit 0).
  */
  popupTerm = pkgs.writeShellApplication {
    name = "popup-term";
    runtimeInputs = [
      pkgs.ghostty
      pkgs.gnugrep
      pkgs.hyprland
    ];
    text = ''
      if ! hyprctl clients | grep -q "com.mitchellh.ghostty.scratch"; then
        hyprctl dispatch 'hl.dsp.exec_cmd("ghostty --class=com.mitchellh.ghostty.scratch", { workspace = "special:term silent" })'
      fi
      hyprctl dispatch 'hl.dsp.workspace.toggle_special("term")'
    '';
  };

  /*
    layerTags — the SOLE source of the six special-workspace "tag"
    names. hyprland.lua's `local tags = {...}` table is generated from
    this list (via pkgs.replaceVars, see xdg.configFile below) rather
    than hand-typed a second time; the bash scripts below interpolate
    it directly since they're already Nix strings. Previously this
    list was duplicated by hand in both places — caught during a
    2026-07-01 code-smell pass alongside the repeated jq query and
    notify-send calls below.
  */
  layerTags = [
    {
      key = "1";
      name = "browser";
    }
    {
      key = "2";
      name = "term";
    } # shares overlay with popup-term
    {
      key = "3";
      name = "music";
    }
    {
      key = "4";
      name = "notes";
    }
    {
      key = "5";
      name = "comms";
    }
    {
      key = "6";
      name = "files";
    }
  ];

  /*
    Generated FROM layerTags, fed into hyprland.lua's `local tags =
    {...}` table via pkgs.replaceVars (see xdg.configFile below) —
    the hand-typed column alignment the old duplicate copy had is
    gone, but there's exactly one place that knows the tag list now.
  */
  layerTagsLua = lib.concatMapStringsSep "\n    " (
    t: "{ key = \"${t.key}\", name = \"${t.name}\" },"
  ) layerTags;

  /*
    spacerClass — the SUPER+G glass-spacer's GTK application id.
    Single source for both the spawn command (plain) and the
    spacer-glass window_rule match (regex-escaped) in hyprland.lua,
    fed in via pkgs.replaceVars. Previously typed twice, with two
    different (and easy to desync) escapings.
  */
  spacerClass = "com.mitchellh.ghostty.spacer";
  spacerClassEscaped = lib.replaceStrings [ "." ] [ "\\\\." ] spacerClass;

  /*
    currentLayer — QUERY only (CQS): prints the bare name of the
    currently-shown special-workspace tag on the focused monitor, or
    an empty string if none is shown. Was three independent
    copy-pasted `hyprctl monitors -j | jq ...` pipelines (layer-cycle,
    layer-toggle, layer-autohide); extracted so a future Hyprland JSON
    schema change only needs fixing in one place.
  */
  currentLayer = pkgs.writeShellApplication {
    name = "current-layer";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
      pkgs.gnused
    ];
    text = ''
      hyprctl monitors -j \
        | jq -r '.[] | select(.focused) | .specialWorkspace.name' \
        | sed 's/^special://'
    '';
  };

  /*
    layer-announce — COMMAND only (CQS): the Persona layer-osd popup
    (capitalized name). Was copy-pasted in layer-cycle and layer-toggle.
  */
  layerAnnounce = pkgs.writeShellApplication {
    name = "layer-announce";
    runtimeInputs = [ pkgs.libnotify ];
    text = ''
      name="$1"
      notify-send -a layer-osd "''${name^}"
    '';
  };

  /*
    layer-cycle — SUPER+ALT+TAB / SUPER+ALT+SHIFT+TAB step through the
    six special-workspace "tags" (browser/term/music/notes/comms/files)
    in order, wrapping. Reads the focused monitor's current special
    workspace via `current-layer` and dispatches a direct `hl.dsp.focus`
    jump to the next/prev tag — NOT toggle_special, since cycling must
    always land on a *different* tag and a toggle could instead hide
    it if Hyprland ever treats same-name re-toggle specially.
  */
  layerCycle = pkgs.writeShellApplication {
    name = "layer-cycle";
    runtimeInputs = [
      currentLayer
      layerAnnounce
      pkgs.hyprland
    ];
    text = ''
      tags=(${lib.concatMapStringsSep " " (t: t.name) layerTags})
      n=''${#tags[@]}

      current="$(current-layer)"

      idx=-1
      for i in "''${!tags[@]}"; do
        if [ "''${tags[$i]}" = "$current" ]; then
          idx=$i
          break
        fi
      done

      case "''${1:-next}" in
        next) next_idx=$(( (idx + 1) % n )) ;;
        prev)
          if [ "$idx" -eq -1 ]; then
            next_idx=$(( n - 1 ))
          else
            next_idx=$(( (idx - 1 + n) % n ))
          fi
          ;;
        *) echo "usage: layer-cycle [next|prev]" >&2; exit 1 ;;
      esac

      hyprctl dispatch "hl.dsp.focus({ workspace = \"special:''${tags[$next_idx]}\" })"
      layer-announce "''${tags[$next_idx]}"
    '';
  };

  /*
    layer-toggle — the tags loop's SUPER+N bind calls this instead of
    dispatching toggle_special directly, so showing a tag also
    announces it (Persona's app-name=layer-osd notification route). Only
    announces on SHOW, not on hide — checks
    whether the tag actually ended up visible after the toggle, since
    toggle_special() can go either direction depending on prior state.
  */
  layerToggle = pkgs.writeShellApplication {
    name = "layer-toggle";
    runtimeInputs = [
      currentLayer
      layerAnnounce
      pkgs.hyprland
    ];
    text = ''
      name="$1"

      hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$name\")" >/dev/null
      shown="$(current-layer)"
      if [ "$shown" = "$name" ]; then
        layer-announce "$name"
      fi
    '';
  };

  /*
    layer-autohide — daemon, started once at hyprland.start. A shown
    special-workspace tag is an overlay on top of whatever regular
    workspace is underneath; Hyprland doesn't auto-dismiss it when you
    switch away (verified empirically 2026-07-01: `activespecial`
    stays set after a `workspace>>` event). This closes that gap by
    watching the live IPC event stream (.socket2.sock) for `workspace>>`
    lines specifically — NOT `activewindow>>`, which also fires for
    focus changes *within* the still-shown tag, and NOT `activespecial>>`,
    which fires for tag-to-tag switches the operator chose on purpose.
    `workspace>>` only fires on a *regular*-workspace change, which is
    exactly "focused something on a lower layer".
  */
  layerAutohide = pkgs.writeShellApplication {
    name = "layer-autohide";
    runtimeInputs = [
      currentLayer
      pkgs.hyprland
      pkgs.socat
    ];
    text = ''
      sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

      socat -u "UNIX-CONNECT:$sock" - | while IFS= read -r line; do
        case "$line" in
          workspace\>\>*)
            shown="$(current-layer)"
            if [ -n "$shown" ]; then
              hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$shown\")" >/dev/null
            fi
            ;;
        esac
      done
    '';
  };

  generatedHyprlandLua = pkgs.replaceVars ./hyprland.lua {
    inherit
      gapsOut
      layerTagsLua
      layoutCore
      nativeLayout
      riceAdapter
      riceCommandBindsLua
      spacerClassEscaped
      ;
  };

  checkedHyprlandLua = pkgs.runCommandLocal "hyprland.lua" { } ''
    ${pkgs.coreutils}/bin/cp ${generatedHyprlandLua} "$out"
    ${pkgs.lua}/bin/luac -p "$out"
    if ${pkgs.gnugrep}/bin/grep -Eq '@[A-Za-z0-9_]+@' "$out"; then
      echo "generated Hyprland Lua contains unresolved template markers" >&2
      exit 1
    fi
    ${pkgs.gnugrep}/bin/grep -Eq 'dofile\("/nix/store/[^\"]+/modules/home/desktop/hypr-rice/rice\.lua"\)' "$out"
    ${pkgs.gnugrep}/bin/grep -Eq '"/nix/store/[^\"]+/modules/home/desktop/hypr-rice/layout\.lua"' "$out"
    ${pkgs.gnugrep}/bin/grep -Fq 'hl.bind(mod .. " + G", hl.dsp.exec_cmd("rice-command utility.glass-spacer"))' "$out"
    ${pkgs.gnugrep}/bin/grep -Fq 'hl.bind(mod .. " + R", hl.dsp.exec_cmd("rice-command layout.ratio"))' "$out"
    ${pkgs.gnugrep}/bin/grep -Fq 'hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd("rice-command layout.menu"))' "$out"
    ${pkgs.gnugrep}/bin/grep -Fq 'hl.bind(mod .. " + L", hl.dsp.exec_cmd("rice-command system.lock"))' "$out"
    ${pkgs.gnugrep}/bin/grep -Fq 'hl.bind(mod .. " + SPACE",  hl.dsp.exec_cmd("rice-palette"))' "$out"
    ! ${pkgs.gnugrep}/bin/grep -Fq 'SHIFT + E' "$out"
    ! ${pkgs.gnugrep}/bin/grep -Fq 'cmd-menu' "$out"
    ! ${pkgs.gnugrep}/bin/grep -Fq 'hypr-cheatsheet"))' "$out"
  '';
in
lib.mkIf config.nori.hyprRice.enable {
  # `hypr-cheatsheet` and `rice-palette` stay on PATH because their
  # command records would otherwise form a store-reference cycle through
  # the generated desktop aggregate.
  home.packages = [
    cheatsheet
    riceCommand # stable command-ID dispatcher and destructive confirmation boundary
    ricePalette # SUPER+SPACE unified applications + rice commands
    hyprPaletteLiveTest # explicit isolated headless compositor journey
    popupTerm # SUPER+RETURN togglable terminal (lazy-spawns its own ghostty)
    glassSpacer # SUPER+G tiled blank glass target
    currentLayer # query: bare name of the shown special-workspace tag, or empty
    layerAnnounce # command: Persona layer-osd popup for a tag name
    layerCycle # SUPER+ALT+TAB / SUPER+ALT+SHIFT+TAB — step through special-workspace tags
    layerToggle # SUPER+N tag toggle, announces via Persona when shown
    layerAutohide # daemon: hides the shown tag when focus moves to a regular workspace
    tileRatio # absolute focused-window ratio on Dwindle
    hyprLayout # strict, hex-encoded bridge into the native rice layout
    hyprLayoutMenu # SUPER+SHIFT+R — presets plus typed custom layout input
    hyprLayoutLiveTest # explicit opt-in real-compositor journey
    hyprSession # hypr-session CLI (list/save/rename/delete/prune/restore)
  ];

  # modules/home/desktop/hypr-lock.nix already owns hyprlock.settings.background
  # (blur + screenshot capture); Stylix's hyprlock target would collide.
  stylix.targets.hyprlock.enable = false;

  wayland.windowManager.hyprland = {
    enable = true;

    /*
      Use the system Hyprland (programs.hyprland.enable = true above).
      Without this home-manager would also install a user-scope copy
      and the two could drift across rebuilds.
    */
    package = null;
    portalPackage = null;

    /*
      Lua is provisioned via xdg.configFile."hypr/hyprland.lua" below.
      configType = "lua" prevents home-manager from rendering a parallel
      hyprland.conf.
    */
    configType = "lua";
  };

  /*
    Hyprland reads this .lua exclusively (configType=lua above).
    Rollback = revert + rebuild; no runtime `rm + reload` shortcut.
    Templated via replaceVars rather than a plain file copy — the tag
    list and the spacer class name are generated in from the single
    Nix-side sources above (layerTagsLua, spacerClass/Escaped) instead
    of being hand-typed a second time directly in the .lua file. The
    file is still a plain, directly-editable Lua file otherwise — only
    the `@name@` markers are special, everything else edits normally.
  */
  xdg.configFile."hypr/hyprland.lua".source = checkedHyprlandLua;

  /*
    hypr-session-logd — subscribes to Hyprland's socket2 event stream and
    debounce-captures full snapshots (see hypr-session/logd.sh header).
    graphical-session.target (not hyprland-session.target specifically)
    matches every other per-session daemon in this file
    (wayland-pipewire-idle-inhibit.nix); Restart=on-failure covers a
    transient socket2-not-up-yet race independent of logd's own
    50x0.1s startup poll.
  */
  systemd.user.services.hypr-session-logd = {
    Unit = {
      Description = "hypr-session: debounced Hyprland window-topology snapshot log";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${hyprSession}/bin/hypr-session-logd";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
