/**
  Minimal operator environment for the headless Adelie bring-up.

  Do not reuse `home.nix`: it intentionally composes a graphical desktop,
  workstation-only symlinks and fleet tooling sized for Emperor's 64 GiB. This
  host needs the common operator recovery tools without turning its first boot
  into a desktop or agent-workstation deployment.
*/
{
  imports = [ ../../profiles/home/core.nix ];

  home.stateVersion = "26.05";
  programs.home-manager.enable = true;
}
