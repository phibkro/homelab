_: {
  # Waybar — status bar at the top of the primary monitor. Auto-starts via
  # systemd user service (programs.waybar.systemd.enable). Style is bare
  # defaults; iterate when something feels rough.
  #
  # Modules:
  #   left   — workspaces (Hyprland), focused-window title
  #   center — wall clock
  #   right  — pulseaudio (click → pwvucontrol), network, system tray
  home-manager.users.nori.programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 28;
        spacing = 6;

        modules-left = [
          "hyprland/workspaces"
          "hyprland/window"
        ];
        modules-center = [ "clock" ];
        modules-right = [
          "pulseaudio"
          "network"
          "tray"
        ];

        "hyprland/workspaces" = {
          format = "{id}";
          on-click = "activate";
        };

        "hyprland/window" = {
          format = "{title}";
          max-length = 80;
          separate-outputs = true;
        };

        clock = {
          format = "{:%a %b %d  %H:%M}";
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
        };

        pulseaudio = {
          format = "{volume}% {icon}";
          format-muted = "muted";
          format-icons = {
            default = [
              ""
              ""
              ""
            ];
          };
          on-click = "pwvucontrol";
          scroll-step = 5;
        };

        network = {
          format-ethernet = "{ifname}";
          format-wifi = "{essid} ({signalStrength}%)";
          format-disconnected = "no net";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}";
        };

        tray = {
          spacing = 8;
          icon-size = 18;
        };
      };
    };
  };
}
