/**
  Reusable Hyprland session profile. It combines the custom rice with the
  session clients without pulling in workstation application bundles.
*/
{
  imports = [
    ../../../users/nori/programs/desktop
    ./wayland-session.nix
  ];

  # Vicinae owns application launching. Avoid Stylix's unused Rofi target,
  # which still writes Home Manager's deprecated `programs.rofi.font` option.
  stylix.targets.rofi.enable = false;
}
