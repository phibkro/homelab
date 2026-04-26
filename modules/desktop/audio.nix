_: {
  # PipeWire with WirePlumber as session manager — the modern default.
  # ALSA + PulseAudio compatibility layers stay enabled for legacy apps
  # (anything still calling `pactl` or opening `/dev/snd/*` directly).
  #
  # JACK left off; flip on if a DAW or low-latency audio app shows up.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # PipeWire claims /dev/snd/* and the legacy stack would race it.
  services.pulseaudio.enable = false;
}
