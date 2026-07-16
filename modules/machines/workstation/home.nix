{
  config,
  pkgs,
  ...
}:
/**
  Pure home-manager module — same shape as every other
  modules/machines/<n>/home.nix. The home-manager-as-NixOS-module wrapper
  lives in the sibling default.nix so this file is portable.
*/
{
  imports = [
    ../../home/pc.nix
    ../../home/desktop
  ];

  home.stateVersion = "26.05"; # match host's system.stateVersion
  programs.home-manager.enable = true;

  home.packages = [
    pkgs.gh # GitHub CLI — PR ops, gh auth, gh api …
    pkgs.nvtopPackages.nvidia # GPU monitor (NVIDIA-only build, smaller closure)
    pkgs.ncdu # interactive disk usage browser
    pkgs.bandwhich # per-process / per-connection network throughput
    pkgs.compsize # btrfs actual-on-disk size + compression ratio
    pkgs.doggo # modern dig — friendlier output
    pkgs.lazysql # SQL TUI (Immich pg, Open WebUI sqlite, etc.)
    pkgs.nix-tree # interactive Nix dependency-graph viewer
    pkgs.nvd # diff between NixOS generations
    pkgs.handbrake # GUI video transcoder (GTK). Mac counterpart is a brew cask — broken on x86_64-darwin in nixpkgs; see modules/machines/macbook/home.nix.
    /*
      pkgs.deno: TS/JS runtime + the security sandbox for `pagu` (the local
      capability-gated agent in the gitignored ./pagu repo). pagu runs on
      Deno and its permission model IS pagu's sandbox, so deno must be on
      PATH; `~/.deno/bin` (deno install targets) is added to PATH below.
    */
    pkgs.deno
    /*
      pkgs.bubblewrap: pagu's OS sandbox tier — when `bwrap` is on PATH, the
      runner wraps each script in a kernel-level wall beneath Deno's perms
      (denies network, confines writes — contains even --allow-run
      subprocesses, which Deno doesn't bound). Optional; pagu falls back to
      the Deno-permission floor without it.
    */
    pkgs.bubblewrap
    /*
      home-manager CLI for introspection (`news`, `generations`). The
      `programs.home-manager.enable` above wires only the activation
      script when HM runs as a NixOS module; the binary isn't auto-
      installed. Don't `home-manager switch` — use `just rebuild`.
    */
    pkgs.home-manager
    pkgs.pulseaudio # pactl — PipeWire/PulseAudio sink/card/port inspection (e.g. fix jack desync after replug)
  ];
  # `deno install -g` drops shims here (e.g. the `pagu` command); put it on
  # PATH so they're runnable from a bare shell.
  home.sessionPath = [ "$HOME/.deno/bin" ];

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
    /*
      color_theme + theme_background managed by Stylix (modules/machines/desktop/
      stylix.nix) via the Material You palette. Set to `default` here
      would override Stylix; leave unset.
    */
  };

  programs.fzf.enable = true; # Ctrl-R history, Ctrl-T file picker, **<Tab> hooks
  programs.zoxide.enable = true; # `z <fragment>` jumps to most-used dir match

  /*
    ~/nori + the standard working folders are out-of-store symlinks into the
    @srv-nori subvolume (networked over Samba + own backup tier). Canonical
    data lives on /srv/nori; apps use the normal home paths; Samba serves the
    real dirs natively (no follow-symlink needed). This is the allowlist shape:
    only these harmless working dirs are relocated onto the share — secrets
    (~/.ssh, ~/.config/sops, ~/.claude.json) stay on @home and never enter the
    shared tree, so there's nothing to filter out. /srv/nori only exists on
    workstation, so this lives here, not in the cross-machine core.nix.
  */
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

}
