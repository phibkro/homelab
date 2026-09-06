{
  config,
  lib,
  pkgs,
  ...
}:
let
  /*
    Glyph codepoints — embedded via builtins.fromJSON so the literal
    PUA characters survive any Edit-tool round-trip. JSON's \uXXXX
    escapes are processed at eval time into real UTF-8 characters in
    the rendered config; printf or shell-quoted-bytes alternatives
    have been flaky in practice.
  */
  msMoon = builtins.fromJSON ''""''; # Material Symbols dark_mode (U+E51C)
  msSun = builtins.fromJSON ''""''; # Material Symbols light_mode (U+E518)
  msVolume = builtins.fromJSON ''""''; # Material Symbols volume_up (U+E050)
  msVolumeOff = builtins.fromJSON ''""''; # Material Symbols volume_off (U+E04F)
in
{
  /**
    Waybar — status bar at the top of the primary monitor. Auto-starts via
    systemd user service (programs.waybar.systemd.enable). Material 3-
    aligned chrome via the CSS override below (corner radius, hover
    state-layer, vertical padding). Material Symbols glyphs for the
    interactive widgets; per-widget font-family override scopes them
    without touching Stylix's main waybar font.

    Modules:
      left   — workspaces (Hyprland), focused-window title
      center — wall clock
      right  — sunset toggle, pulseaudio (click → pwvucontrol), network, tray
  */
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    /*
      Waybar 0.15.0 forgets to free vanished StatusNotifier watch records.
      Carry the verified upstream MIT-licensed fix until nixpkgs ships it:
      https://github.com/Alexays/Waybar/commit/78f6cde232147ee98986edd3cacfe9c6570bd7ec
    */
    package = pkgs.waybar.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (pkgs.fetchurl {
          name = "waybar-free-vanished-sni-watches.diff";
          url = "https://github.com/Alexays/Waybar/commit/78f6cde232147ee98986edd3cacfe9c6570bd7ec.diff";
          hash = "sha256-n9zMxOYcsQv82xOqE3TRBkQC5qYRgmJBL92XxY7Odec=";
        })
      ];
    });
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        /*
          Height auto-sizes to content + CSS padding (no fixed value);
          the bar grows / shrinks with font size for ~2em vertical
          rhythm. CSS adds 6px top/bottom padding.
        */
        spacing = 6;
        # Margin off the screen edges — matches Hyprland's gaps_out=8
        # so the bar's left/right edges align with the windows below.
        margin-top = 8;
        margin-left = 8;
        margin-right = 8;

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

        /*
          Glyph-only audio button — click → pwvucontrol mixer. Volume
          percentage dropped: the mixer GUI shows it; saves bar real-
          estate. Muted state swaps glyph (volume_off has the slash).
        */
        pulseaudio = {
          format = "{icon}";
          format-muted = msVolumeOff;
          format-icons = {
            default = [ msVolume ];
          };
          on-click = "${pkgs.systemd}/bin/systemctl --user start pwvucontrol.service";
          scroll-step = 5;
          tooltip-format = "{volume}% — click for mixer";
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

        /*
          Blue-light filter toggle via systemd user unit. hyprsunset's
          CLI is one-shot (no live IPC in 0.3.x), so toggle = start/
          stop the daemon; on stop hyprsunset restores neutral gamma
          before exiting. Glyph flips with active-state.
        */
        "custom/sunset" = {
          format = "{}";
          interval = 5;
          exec = "systemctl --user is-active --quiet hyprsunset && echo '${msMoon}' || echo '${msSun}'";
          on-click = "systemctl --user is-active --quiet hyprsunset && systemctl --user stop hyprsunset || systemctl --user start hyprsunset";
          tooltip-format = "Click: toggle blue-light filter";
        };
      };
    };
    /*
      Material 3 chrome appended on top of Stylix's base CSS:
        * 12dp bar corner
        * 6px top/bottom inner padding for ~2em vertical rhythm
        * 8dp horizontal padding per module group + per module
        * Hover state-layer on interactive widgets (M3 hover token —
          ~8% primary tint on surface)
        * Material Symbols Outlined font for icon-only widgets
    */
    style = ''
      window#waybar {
          border-radius: 12px;
          padding: 6px 0;
      }
      .modules-left, .modules-center, .modules-right {
          padding: 0 8px;
      }
      #workspaces button, /* multi-line: ok — CSS selectors, not Nix comments */
      #window,
      #clock,
      #pulseaudio,
      #network,
      #tray,
      #custom-sunset {
          padding: 0 8px;
      }
      /* M3 hover state-layer for interactive widgets. */
      #custom-sunset:hover,
      #pulseaudio:hover {
          background: alpha(@base05, 0.08);
          border-radius: 8px;
      }
      /* Icon-only widgets render via Material Symbols Outlined.
         JetBrainsMono Nerd Font Mono kept as fallback in case the
         glyph isn't in Symbols (won't happen for current set). */
      #custom-sunset,
      #pulseaudio {
          font-family: "Material Symbols Outlined", "JetBrainsMono Nerd Font Mono";
          font-size: 16px;
      }
    '';
  };

  /*
    Own the mixer as its own session service. Launching it directly from a
    Waybar click charged its GTK process and retained file cache to Waybar's
    cgroup, which made the resource detector report the bar as the owner.
  */
  systemd.user.services.pwvucontrol = {
    Unit = {
      Description = "PipeWire volume control";
      PartOf = [ config.wayland.systemd.target ];
      After = [ config.wayland.systemd.target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      Type = "exec";
      ExecStart = "${pkgs.pwvucontrol}/bin/pwvucontrol";
      Restart = "no";
    };
  };

  /*
    Home Manager also binds Waybar to tray.target. That target belongs to the
    persistent user manager, not one compositor instance, so it can start the
    bar at the greeter and exhaust the restart budget before Hyprland exists.
    Keep the generated unit, but give it the same single lifecycle owner as
    every other Wayland daemon in this desktop composition.
  */
  systemd.user.services.waybar = {
    Unit = {
      PartOf = lib.mkForce [ config.wayland.systemd.target ];
      After = lib.mkForce [ config.wayland.systemd.target ];
    };
    Install.WantedBy = lib.mkForce [ config.wayland.systemd.target ];
  };
}
