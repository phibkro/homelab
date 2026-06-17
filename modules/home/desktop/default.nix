_: {
  /**
    Home-manager modules for the Wayland/Hyprland graphical session.
    Imported by `modules/machines/workstation/home.nix` (Linux NixOS desktop).
    NOT imported by macbook — its standalone home-manager goes through
    `modules/home/pc.nix` directly + uses brew/cask for GUI surfaces.
  */
  imports = [
    ./apps.nix
    ./hypr-lock.nix
    ./hyprsunset.nix
    ./mako.nix
    ./waybar.nix
    ./wayland-pipewire-idle-inhibit.nix
  ];
}
