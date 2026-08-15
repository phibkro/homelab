_: {
  /**
    Private implementation modules for the Wayland/Hyprland session.
    The public composition boundary is profiles/desktop/default.nix.
  */
  imports = [
    ./hypr-lock.nix
    ./hypr-rice
    ./hyprsunset.nix
    ./persona-quickshell
    ./waybar.nix
    ./wayland-pipewire-idle-inhibit.nix
  ];

  nori.hyprRice.enable = true;
}
