{
  pkgs,
  lib,
  ...
}:
let
  nativeLayout = "dwindle";
  layoutCore = ./layout.lua;
  riceAdapter = ./rice.lua;

  /*
    ---------------------------------------------------------------------
    Bind data — single source of truth for the Hyprland config + the
    SUPER+H cheatsheet. Records are built via the small constructor set
    below; each carries:
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
    (mkBindApp "R" "hypr-layout-menu" "workspace layout")

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

  cheatsheet = pkgs.writeShellScriptBin "hypr-cheatsheet" ''
    cat ${cheatsheetFile} | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "binds: " --width 64 --lines 24 >/dev/null
  '';

  # fuzzel-driven system-action menu. Destructive entries gate behind
  # a yes/no confirm.
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

  hyprLayout = pkgs.writeShellApplication {
    name = "hypr-layout";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./hypr-layout.sh;
  };

  hyprLayoutMenu = pkgs.writeShellApplication {
    name = "hypr-layout-menu";
    runtimeInputs = [
      pkgs.fuzzel
      hyprLayout
    ];
    text = ''
      set +e
      choice="$(${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "layout: " <<'EOF'
      1 1
      1 2 1
      repeat(1,5)
      a b; a .; c c
      reset
      EOF
      )"
      status=$?
      set -e
      [[ $status -eq 1 ]] && exit 0
      [[ $status -eq 0 ]] || exit "$status"
      [[ -n "$choice" ]] || exit 0
      if [[ "$choice" == reset ]]; then
        hypr-layout reset
      else
        hypr-layout "$choice"
      fi
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
  popupTerm = pkgs.writeShellScriptBin "popup-term" ''
    if ! hyprctl clients | grep -q "com.mitchellh.ghostty.scratch"; then
      hyprctl dispatch 'hl.dsp.exec_cmd("ghostty --class=com.mitchellh.ghostty.scratch", { workspace = "special:term silent" })'
    fi
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("term")'
  '';

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
  currentLayer = pkgs.writeShellScriptBin "current-layer" ''
    set -euo pipefail
    hyprctl monitors -j \
      | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .specialWorkspace.name' \
      | sed 's/^special://'
  '';

  /*
    layer-announce — COMMAND only (CQS): the mako layer-osd popup
    (capitalized name). Was copy-pasted in layer-cycle and layer-toggle.
  */
  layerAnnounce = pkgs.writeShellScriptBin "layer-announce" ''
    set -euo pipefail
    name="$1"
    ${pkgs.libnotify}/bin/notify-send -a layer-osd "''${name^}"
  '';

  /*
    layer-cycle — SUPER+ALT+TAB / SUPER+ALT+SHIFT+TAB step through the
    six special-workspace "tags" (browser/term/music/notes/comms/files)
    in order, wrapping. Reads the focused monitor's current special
    workspace via `current-layer` and dispatches a direct `hl.dsp.focus`
    jump to the next/prev tag — NOT toggle_special, since cycling must
    always land on a *different* tag and a toggle could instead hide
    it if Hyprland ever treats same-name re-toggle specially.
  */
  layerCycle = pkgs.writeShellScriptBin "layer-cycle" ''
    set -euo pipefail
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

  /*
    layer-toggle — the tags loop's SUPER+N bind calls this instead of
    dispatching toggle_special directly, so showing a tag also
    announces it (mako's app-name=layer-osd criteria, modules/home/
    desktop/mako.nix). Only announces on SHOW, not on hide — checks
    whether the tag actually ended up visible after the toggle, since
    toggle_special() can go either direction depending on prior state.
  */
  layerToggle = pkgs.writeShellScriptBin "layer-toggle" ''
    set -euo pipefail
    name="$1"

    hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$name\")" >/dev/null
    shown="$(current-layer)"
    if [ "$shown" = "$name" ]; then
      layer-announce "$name"
    fi
  '';

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
  layerAutohide = pkgs.writeShellScriptBin "layer-autohide" ''
    set -euo pipefail
    socat=${pkgs.socat}/bin/socat
    sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

    "$socat" -u "UNIX-CONNECT:$sock" - | while IFS= read -r line; do
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

  generatedHyprlandLua = pkgs.replaceVars ./hyprland.lua {
    inherit
      layerTagsLua
      layoutCore
      nativeLayout
      riceAdapter
      spacerClass
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
  '';
in
{
  /*
    Cheatsheet on PATH. Referenced by SUPER+H as `hypr-cheatsheet`
    (name, not store path) — avoids the cycle where the binding's
    store path would depend on the cheatsheet text which depends on
    the bindings.
  */
  home.packages = [
    cheatsheet
    cmdMenu # SUPER+P command menu (lock / night mode / reboot / power off)
    popupTerm # SUPER+RETURN togglable terminal (lazy-spawns its own ghostty)
    currentLayer # query: bare name of the shown special-workspace tag, or empty
    layerAnnounce # command: mako layer-osd popup for a tag name
    layerCycle # SUPER+ALT+TAB / SUPER+ALT+SHIFT+TAB — step through special-workspace tags
    layerToggle # SUPER+N tag toggle, announces via mako when shown
    layerAutohide # daemon: hides the shown tag when focus moves to a regular workspace
    hyprLayout # strict, hex-encoded bridge into the native rice layout
    hyprLayoutMenu # SUPER+R — presets plus typed custom layout input
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
}
