_: {
  # Required for proper screen sharing under PipeWire+Wayland — the
  # xdg-desktop-portal screencast path goes over the session bus.
  # NixOS enables dbus by default, so this is largely belt-and-suspenders.
  services.dbus.enable = true;

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

  # Pin the onboard Realtek ALC892 analog sink as the preferred default
  # device. Without this, wireplumber's "most recently connected /
  # highest-capability" heuristic ends up promoting the Svive USB mic's
  # playback monitor (a sidetone loopback, not real speakers) — anything
  # plugged into the motherboard's 3.5mm jacks then plays into the void.
  #
  # Match by `alsa.mixer_name` (the codec ID) instead of node.name or
  # PCI path so this survives PCI renumbering and USB device shuffling.
  # `wpctl set-default` writes a per-user override to
  # ~/.local/state/wireplumber/default-nodes; this rule belt-and-suspenders
  # the priority for fresh users / wiped state.
  environment.etc."wireplumber/wireplumber.conf.d/51-prefer-onboard-analog.conf".text = ''
    monitor.alsa.rules = [
      {
        matches = [
          {
            alsa.mixer_name = "Realtek ALC892"
            media.class = "Audio/Sink"
          }
        ]
        actions = {
          update-props = {
            priority.driver  = 2000
            priority.session = 2000
          }
        }
      }
    ]
  '';
}
