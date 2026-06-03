---
name: gotcha-wireplumber-usb-mic-sink
description: USE WHEN audio plays into the void after plugging in a USB streaming mic (Svive Leo / RØDE NT-USB / etc.) — Wireplumber's "highest capability" heuristic promotes the mic's sidetone monitor sink ahead of motherboard analog. Fix: wireplumber rule matching by `alsa.mixer_name` (codec ID, hardware-stable; NOT `node.name` or PCI path).
---

# Wireplumber promotes the wrong sink as default for USB streaming mics

USB streaming mics (Svive Leo, RØDE NT-USB, etc.) expose a playback sink as a sidetone monitor — not real speakers. Wireplumber's "highest capability" heuristic ranks USB devices ahead of onboard analog, so the mic's monitor sink ends up default. Anything plugged into the motherboard 3.5mm jacks plays into the void; volume sliders move but nothing comes out of the headphones.

`wpctl set-default <id>` writes a per-user override (`~/.local/state/wireplumber/default-nodes`) that survives reboots, but a wireplumber rule belt-and-suspenders the priority for fresh users / wiped state:

```nix
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
```

Match by `alsa.mixer_name` (the codec ID), not `node.name` or PCI path — the codec name is hardware-stable while PCI paths shift with USB device ordering.
