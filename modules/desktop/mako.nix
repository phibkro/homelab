_: {
  # Mako — Wayland notification daemon. Picks up `notify-send` from any
  # CLI / app and renders toasts in the corner. home-manager provisions
  # a systemd user service that starts at session login.
  #
  # Defaults are sensible; the only knob set is corner radius matching
  # Hyprland's `decoration.rounding = 4` for visual consistency.
  home-manager.users.nori.services.mako = {
    enable = true;
    settings = {
      default-timeout = 5000; # 5s
      border-radius = 4;
      border-size = 2;
      max-visible = 5;
      anchor = "top-right";
      margin = "12";
      padding = "10";
    };
  };
}
