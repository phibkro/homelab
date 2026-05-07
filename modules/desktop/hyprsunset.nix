_: {
  # hyprsunset — color temperature shifter (blue-light filter). Warms
  # the screen in the evening; reverts to neutral in the morning.
  # Activated as a home-manager systemd user service so it runs alongside
  # the rest of the Hyprland session (started via UWSM's
  # graphical-session.target — same lifecycle as waybar/mako/hypridle).
  #
  # Schedule is fixed times rather than astronomical sunrise/sunset
  # because Oslo's daylight swing is so extreme (~6h winter / ~18h
  # summer) that an astronomical schedule would have you on warm-mode
  # at noon in December and never at all in June. Fixed evening/
  # morning transitions give a consistent felt-time experience.
  #
  # Tuning:
  #   day    6500K  neutral / cool — sRGB-accurate
  #   night  3500K  warm — easier on the eyes for late work
  # Drop night to 3000K if 3500K still feels cold late at night;
  # raise day to 7000K if the daytime feels yellowish.
  home-manager.users.nori.services.hyprsunset = {
    enable = true;
    settings = {
      max-gamma = 100;
      # Profiles fire at the given time and stay active until the
      # next profile takes over. `identity = true` on the daytime
      # entry is the canonical way to express "no temperature shift"
      # — equivalent to 6500K but skips the colour-matrix math.
      profile = [
        {
          time = "07:00:00";
          identity = true;
        }
        {
          time = "20:00:00";
          temperature = 3500;
        }
      ];
    };
  };
}
