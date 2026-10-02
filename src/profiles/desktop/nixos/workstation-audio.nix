_: {
  /*
    Pin the workstation's onboard Realtek ALC892 analog sink as the preferred
    default device. Without this, WirePlumber can promote the Svive USB mic's
    playback monitor rather than the motherboard's 3.5 mm speakers.

    Match the codec ID instead of a node name or PCI path so USB shuffling and
    PCI renumbering do not change the policy. This hardware-specific rule stays
    out of the reusable graphical desktop composition.

    The Svive mic's card otherwise comes up in the output-only
    `output:iec958-stereo` profile, which exposes no capture source, so Discord
    sees no microphone. Select the input-only profile on the card and prefer its
    source over the onboard front-mic jack, which has nothing plugged in.
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

  environment.etc."wireplumber/wireplumber.conf.d/52-svive-mic-input.conf".text = ''
    monitor.alsa.rules = [
      {
        matches = [
          { device.name = "alsa_card.usb-USB_Microphone_Svive_Leo_Studio_mic_2019_07_10-00" }
        ]
        actions = {
          update-props = {
            device.profile = "input:analog-stereo"
          }
        }
      }
      {
        matches = [
          {
            node.name = "~alsa_input.usb-USB_Microphone_Svive_Leo_Studio_mic_.*"
            media.class = "Audio/Source"
          }
        ]
        actions = {
          update-props = {
            priority.driver  = 2500
            priority.session = 2500
          }
        }
      }
    ]
  '';
}
