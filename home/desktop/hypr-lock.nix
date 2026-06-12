_: {
  # Pair: hyprlock (the actual lock screen UI) + hypridle (the inactivity
  # daemon that calls hyprlock and turns the monitor off). Both ship from
  # the Hyprland project; they're designed to work together.
  #
  # Idle ladder (desktop, no battery — skip dim-via-brightnessctl):
  #   10 min  → hyprlock + dpms off in one go (lock implies sleep monitor)
  #   on-input → Hyprland auto-wakes monitor (no explicit on-resume needed)
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
        # 1s sleep before exec guards against the home-manager
        # activation race where hyprlock briefly isn't on PATH
        # while user-profile symlinks swap — caught 2026-06-07 when
        # a `just rebuild` immediately triggered the lock and
        # hyprlock failed to spawn (Hyprland's "no lock app"
        # fallback engaged + monitors stayed lit). The sleep is
        # imperceptible at lock time; only matters during rebuilds.
        #
        # DPMS off is chained inline (background hyprlock, then
        # dispatch dpms off after a 2s settle) so monitor sleep is
        # tied to the lock event itself, not a separate idle timer
        # that can fire mid-password-entry.
        lock_cmd = ''(pidof hyprlock || (sleep 1 && hyprlock)) & sleep 2 && hyprctl dispatch 'hl.dsp.dpms("off")' '';
        # Lock before suspending so wake lands on the lock screen.
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = ''hyprctl dispatch 'hl.dsp.dpms("on")' '';
        # Don't honor browser-tab ScreenSaver inhibits. Caught
        # 2026-06-08: Zen browser held a "Playing video" inhibit
        # overnight (backgrounded autoplay tab) while a user@1000
        # leak climbed to 26.2G RSS + 21.5G swap peak and global-
        # OOM'd at 01:53. Without sleep firing, the leak had
        # unbounded runway. Browser autoplay shouldn't be able to
        # keep the machine awake; if a real long-running task needs
        # to run, use `systemd-inhibit` explicitly (logind path —
        # not affected by this flag).
        ignore_dbus_inhibit = true;
      };
      listener = [
        {
          timeout = 600; # 10 min → lock + dpms off
          # Invoke hyprlock directly rather than via `loginctl
          # lock-session`: hypridle runs under the systemd user manager
          # (user@1000), not pinned to the graphical logind session, so
          # with multiple live sessions the Lock signal didn't reach
          # hyprlock. `pidof` guard prevents stacking lock instances.
          #
          # DPMS off is chained inline (1s settle for the lock surface
          # to render before the dispatch) rather than living in a
          # separate later-timeout listener. Hyprland wakes the monitor
          # automatically on input, so no on-resume hook is needed.
          on-timeout = ''(pidof hyprlock || hyprlock) & sleep 1 && hyprctl dispatch 'hl.dsp.dpms("off")' '';
        }
      ];
    };
  };
}
