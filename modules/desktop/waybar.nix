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
          # printf with explicit UTF-8 byte escapes — Material Symbols
          # codepoints (U+E51C dark_mode, U+E518 light_mode) live in
          # the Private Use Area and don't survive copy-paste through
          # editors that normalize PUA to nothing. \xee\x94\x9c is the
          # 3-byte UTF-8 encoding of U+E51C; \xee\x94\x98 of U+E518.
          exec = "systemctl --user is-active --quiet hyprsunset && printf '\\xee\\x94\\x9c' || printf '\\xee\\x94\\x98'";
          on-click = "systemctl --user is-active --quiet hyprsunset && systemctl --user stop hyprsunset || systemctl --user start hyprsunset";
          tooltip-format = "Click: toggle blue-light filter";
        };
      };
    };
    # Stylix owns the bulk of the waybar CSS (palette + base font).
    # Append Material 3-aligned chrome:
    #   * 12px (12dp) bar corner — Material card token
    #   * 8/12px padding on 4dp grid
    #   * #custom-sunset uses Material Symbols Outlined for the icon
    # See feedback/material_you_design memory for the design system.
    style = ''
      window#waybar {
          border-radius: 12px;
      }
      .modules-left, .modules-center, .modules-right {
          padding: 0 8px;
      }
      #workspaces button,
      #window,
      #clock,
      #pulseaudio,
      #network,
      #tray,
      #custom-sunset {
          padding: 0 8px;
      }
      #custom-sunset {
          font-family: "Material Symbols Outlined", "JetBrainsMono Nerd Font Mono";
          font-size: 16px;
      }
    '';
  };
}
