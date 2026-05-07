_: {
  # Waybar — status bar at the top of the primary monitor. Auto-starts via
  # systemd user service (programs.waybar.systemd.enable). Style is bare
  # defaults; iterate when something feels rough.
  #
  # Modules:
  #   left   — workspaces (Hyprland), focused-window title
  #   center — wall clock
  #   right  — sunset toggle, pulseaudio (click → pwvucontrol), network, tray
  home-manager.users.nori.programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 28;
        spacing = 6;
        # Margin off the screen edges. Combined with rounded corners
        # (Stylix-themed) the bar reads as a floating pill rather than
        # a hard rail.
        margin-top = 6;
        margin-left = 12;
        margin-right = 12;

        modules-left = [
          "hyprland/workspaces"
          "hyprland/window"
        ];
        modules-center = [ "clock" ];
        modules-right = [
          "custom/sunset"
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

        # Blue-light filter toggle via systemd user unit. hyprsunset's
        # CLI is one-shot (no live IPC in 0.3.x), so toggle = start/
        # stop the daemon; on stop hyprsunset restores neutral gamma
        # before exiting. Icon flips with active-state — Material
        # Symbols glyphs (dark_mode U+E51C / light_mode U+E518). The
        # CSS override below sets the font to Material Symbols Outlined
        # for this widget only — the codepoints live in the PUA range
        # which JetBrainsMono Nerd Font doesn't cover.
        "custom/sunset" = {
          format = "{}";
          interval = 5;
          exec = "systemctl --user is-active --quiet hyprsunset && echo  || echo ";
          on-click = "systemctl --user is-active --quiet hyprsunset && systemctl --user stop hyprsunset || systemctl --user start hyprsunset";
          tooltip-format = "Click: toggle blue-light filter";
        };
      };
    };
    # Stylix owns the bulk of the waybar CSS (palette, fonts, spacing).
    # Append a small override so #custom-sunset falls back to Material
    # Symbols for its icon glyph.
    style = ''
      #custom-sunset {
          font-family: "Material Symbols Outlined", "JetBrainsMono Nerd Font Mono";
          font-size: 16px;
      }
    '';
  };
}
