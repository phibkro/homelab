_: {
  /*
    Reusable local graphical desktop composition. The workstation `desktop`
    profile extends this with its gaming, virtualization, Sunshine, and
    host-specific audio policy.
  */
  imports = [
    ./hyprland.nix
    ./plasma.nix
    ../../../services/greetd/nixos.nix
    ./audio.nix
    ./apps.nix
    ./fonts.nix
    ./stylix.nix
    ./wayland.nix
    ./desktop-settings-activation.nix
  ];
}
