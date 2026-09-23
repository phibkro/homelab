_: {
  /*
    Pin the workstation's onboard Realtek ALC892 analog sink as the preferred
    default device. Without this, WirePlumber can promote the Svive USB mic's
    playback monitor rather than the motherboard's 3.5 mm speakers.

    Match the codec ID instead of a node name or PCI path so USB shuffling and
    PCI renumbering do not change the policy. This hardware-specific rule stays
    out of the reusable graphical desktop composition.
  */
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
