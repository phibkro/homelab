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

  /*
    This desktop is Hyprland-only, so Wayland daemons belong to the
    compositor's session target rather than the generic graphical target.
    The user manager persists across logouts; graphical-session.target can
    therefore remain active at the greeter and leave failed services inert on
    the next login. hyprland-session.target is bounced after Hyprland imports
    its fresh display environment, giving every dependent one lifecycle root.
  */
  wayland.systemd.target = "hyprland-session.target";

  nori.hyprRice.enable = true;
}
