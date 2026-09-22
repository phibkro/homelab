_: {
  /**
    Workstation-only graphical capabilities. The inventory composes this after
    the reusable graphical-desktop profile.
  */
  imports = [
    ./gaming.nix
    ./virt.nix
    ./workstation-audio.nix
    ../../../services/sunshine/nixos.nix
  ];
}
