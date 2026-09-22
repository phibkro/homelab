/**
  Reusable Hyprland session profile. It combines the custom rice with the
  session clients without pulling in workstation application bundles.
*/
{
  imports = [
    ../../../users/nori/programs/desktop
    ./wayland-session.nix
  ];
}
