/**
  Minimal graphical operator environment for Adelie.

  It reuses shared core tools and the Hyprland session without importing the
  workstation profile or workstation-only application groups.
*/
{
  imports = [
    ../../profiles/home/core.nix
    ../../profiles/home/desktop/hyprland-session.nix
  ];
  home.stateVersion = "26.05";

  # Stylix supplies the cursor values; Home Manager requires explicit generation.
  home.pointerCursor.enable = true;
  programs.home-manager.enable = true;
}
