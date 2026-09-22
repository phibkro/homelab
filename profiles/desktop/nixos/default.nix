_: {
  /**
    Workstation graphical desktop superset. Shared local-session concerns live
    in graphical-desktop.nix; this profile adds only workstation capabilities.
  */
  imports = [
    ./graphical-desktop.nix
    ./gaming.nix
    ./virt.nix
    ./workstation-audio.nix
    ../../../services/sunshine/nixos.nix
  ];
}
