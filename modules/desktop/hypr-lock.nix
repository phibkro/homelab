_: {
  # Pair: hyprlock (the actual lock screen UI) + hypridle (the inactivity
  # daemon that calls hyprlock and turns the monitor off). Both ship from
  # the Hyprland project; they're designed to work together.
  #
  # Idle ladder (desktop, no battery — skip dim-via-brightnessctl):
  #   10 min  → hyprlock directly  (see on-timeout note below)
  #   15 min  → hyprctl dispatch dpms off (monitor sleep)
  #   on-resume → dpms on (re-wake monitor)
  #
  # No suspend listener — desktop, always-on, persistent services
  # (Caddy / Authelia / etc.) shouldn't be paused.
  home-manager.users.nori = {
    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          hide_cursor = true;
          grace = 2; # ignore input for 2s after wake to avoid accidental unlock
          ignore_empty_input = true;
        };

        background = [
          {
            path = "screenshot";
            blur_passes = 3;
            blur_size = 8;
          }
        ];

        label = [
          {
            text = "$TIME";
            color = "rgba(220, 220, 220, 1.0)";
            font_size = 96;
            font_family = "JetBrainsMono Nerd Font";
            position = "0, 220";
            halign = "center";
            valign = "center";
          }
        ];

        input-field = [
          {
            size = "320, 56";
            position = "0, -120";
            halign = "center";
            valign = "center";
            outline_thickness = 2;
            dots_size = 0.3;
            dots_spacing = 0.3;
            fade_on_empty = true;
            placeholder_text = "Password";
            check_color = "rgba(204, 153, 255, 1.0)";
          }
        ];
      };
    };

    services.hypridle = {
      enable = true;
      settings = {
        general = {
          # Wrapped to prevent multiple lock instances stacking up.
          lock_cmd = "pidof hyprlock || hyprlock";
          # before_sleep_cmd left unset — desktop doesn't sleep.
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };
        listener = [
          {
            timeout = 600; # 10 min → lock
            # Invoke hyprlock directly rather than via `loginctl
            # lock-session`: hypridle runs under the systemd user manager
            # (user@1000), not pinned to the graphical logind session, so
            # with multiple live sessions the Lock signal didn't reach
            # hyprlock. `pidof` guard prevents stacking lock instances.
            on-timeout = "pidof hyprlock || hyprlock";
          }
          {
            timeout = 900; # 15 min → DPMS off
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on";
          }
        ];
      };
    };
  };
}
