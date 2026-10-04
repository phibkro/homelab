{ lib, pkgs, ... }:
/*
  hyprsunset — color temperature shifter (blue-light filter). Warms
  the screen in the evening; reverts to neutral in the morning.
  Activated as a home-manager systemd user service so it runs alongside
  the rest of the Hyprland session under the compositor-specific target
  shared by Persona, Waybar, and hypridle.

  Schedule is fixed times rather than astronomical sunrise/sunset
  because Oslo's daylight swing is so extreme (~6h winter / ~18h
  summer) that an astronomical schedule would have you on warm-mode
  at noon in December and never at all in June. Fixed evening/
  morning transitions give a consistent felt-time experience.

  Tuning:
    day    identity  no colour change
    night  3500K     warm — easier on the eyes for late work
  Drop night to 3000K if 3500K still feels cold late at night.
*/
let
  nightTemperature = 3500;
  # Off reports this temperature. The CTM is identity, because 6500K
  # itself still dims blue by about 2% in hyprsunset 0.4.
  neutralTemperature = 6500;

  /*
    Manual override at any time of day (Waybar button, Vicinae command).
    It changes the running daemon through hyprsunset's IPC, so the next
    scheduled profile still takes over at 07:00 or 20:00. "On" means the
    daemon runs at a temperature below neutral; the daytime profile sets
    the neutral temperature alongside `identity`, because the IPC query
    reports only the last temperature.
  */
  nightMode = pkgs.writeShellApplication {
    name = "night-mode";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
      pkgs.systemd
    ];
    text = ''
      current() {
        local t
        t="$(hyprctl hyprsunset temperature 2>/dev/null || true)"
        [[ $t =~ ^[0-9]+$ ]] && printf '%s\n' "$t"
      }

      is_on() {
        local t
        systemctl --user is-active --quiet hyprsunset || return 1
        t="$(current)" || return 1
        ((t < ${toString neutralTemperature}))
      }

      case "''${1:-}" in
        status)
          if is_on; then echo on; else echo off; fi
          ;;
        toggle)
          if is_on; then
            hyprctl hyprsunset temperature ${toString neutralTemperature} >/dev/null
            hyprctl hyprsunset identity >/dev/null
          else
            systemctl --user start hyprsunset
            for _ in $(seq 50); do
              current >/dev/null && break
              sleep 0.1
            done
            hyprctl hyprsunset temperature ${toString nightTemperature} >/dev/null
          fi
          ;;
        *)
          echo "usage: night-mode {status|toggle}" >&2
          exit 64
          ;;
      esac
    '';
  };
in
{
  options.nori.nightMode.command = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = lib.getExe nightMode;
    description = ''
      `night-mode status|toggle`: query or flip the blue-light filter at
      any time; the hyprsunset schedule resumes at its next profile.
    '';
  };

  config = {
    home.packages = [ nightMode ];

    services.hyprsunset = {
      enable = true;
      settings = {
        max-gamma = 100;
        /*
          Profiles fire at the given time and stay active until the
          next profile takes over.
        */
        profile = [
          {
            time = "07:00:00";
            temperature = neutralTemperature;
            identity = true;
          }
          {
            time = "20:00:00";
            temperature = nightTemperature;
          }
        ];
      };
    };
  };
}
