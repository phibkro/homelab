_: {
  /*
    Reusable local graphical desktop composition. The workstation `desktop`
    profile extends this with its gaming, virtualization, and host-specific
    audio policy.
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
    ./remote-desktop.nix
    ./desktop-settings-activation.nix
  ];
}
