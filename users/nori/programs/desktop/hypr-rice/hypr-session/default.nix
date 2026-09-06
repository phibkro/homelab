{ pkgs, lib, ... }:
let
  /*
    All four scripts land in ONE $out/bin, kept at the literal filenames
    logd.sh/cli.sh/restore.sh already assume for each other:
      - cli.sh delegates `restore` via `dirname "${BASH_SOURCE[0]}"`/restore.sh
      - logd.sh defaults HYPR_SESSION_CAPTURE_CMD to the same script_dir's
        capture.sh
    (see each script's header — "runtime closure, not PATH luck", design
    doc § Packaging). Colocation in one derivation is what makes that
    resolve correctly once Nix-wrapped; splitting these into separate
    writeShellApplication derivations would break both sibling lookups.
    `hypr-session` and `hypr-session-logd` get the human-facing names;
    capture.sh/restore.sh keep their script-internal names since the
    scripts above hard-code them.
  */
  unwrapped = pkgs.runCommandLocal "hypr-session-unwrapped" { } ''
    mkdir -p "$out/bin"
    install -m755 ${./capture.sh} "$out/bin/capture.sh"
    install -m755 ${./restore.sh} "$out/bin/restore.sh"
    install -m755 ${./logd.sh} "$out/bin/hypr-session-logd"
    install -m755 ${./cli.sh} "$out/bin/hypr-session"
    # Sourced, never executed directly — state-dir default + the
    # class-adapter table capture.sh/restore.sh both consult + the
    # ring-prune primitive logd.sh/cli.sh both consult. Same sibling-
    # directory lookup as the other four (script_dir-relative), so it
    # must land in this same $out/bin.
    install -m644 ${./lib.sh} "$out/bin/lib.sh"
  '';

  # Closed over on every entry point — login PATH has no jq/socat, and
  # hyprctl needs to be the same Hyprland the compositor itself runs
  # (programs.hyprland.enable = true elsewhere; pkgs.hyprland here is the
  # matching system package, not a second home-manager-scoped copy).
  runtimeDeps = [
    pkgs.jq
    pkgs.coreutils
    pkgs.hyprland
    pkgs.socat
    pkgs.bash
  ];
in
pkgs.symlinkJoin {
  name = "hypr-session";
  paths = [ unwrapped ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    for bin in capture.sh restore.sh hypr-session-logd hypr-session; do
      wrapProgram "$out/bin/$bin" --prefix PATH : ${lib.makeBinPath runtimeDeps}
    done
  '';
}
