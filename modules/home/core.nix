{ pkgs, ... }:

/**
  Cross-platform Home Manager core, selected through profiles/core.nix.
  This contains the small operational baseline; development and agent
  tooling live in capability modules beside the profiles.

  Pi receives this too. Heavy packages (Claude Code → Node, desktop and
  creative tooling) are selected by narrower profiles or machine roles so
  the Pi's anti-write USB SSD does not carry packages it cannot use.
*/

{
  home.packages = with pkgs; [
    comma # `, <pkg>` runs nix packages ad-hoc
    tmux
    age
    sops
  ];
}
