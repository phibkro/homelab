---
date: 2026-09-22
status: accepted — governing design for feat/dual-desktop-sessions
owner: operator
implementation_branch: feat/dual-desktop-sessions
summary: Provide Plasma and the existing UWSM Hyprland rice as local login sessions on workstation and Adelie.
---

# Design — dual desktop sessions

## Decision summary

Provide two local Wayland sessions on both NixOS hosts:

```text
greetd + tuigreet
├── Plasma
└── Hyprland through UWSM
```

Keep greetd as the only login manager. Keep Hyprland as the initial fallback.
Tuigreet remembers the session that each user selects.

Create a shared `graphical-desktop` system profile for login and session
concerns. Keep gaming, virtualization, Sunshine, and workstation applications
in the existing workstation `desktop` profile.

Create a reusable Hyprland Home Manager profile. Adelie uses this profile
without the workstation development and creative application profiles.

## Goal

The operator can select Plasma or the existing Hyprland rice at the local login
screen on workstation and Adelie. Each session starts only its own services.
Existing server workloads continue to start independently of graphical login.

## Constraints

- Greetd remains the only login manager.
- Automatic login remains disabled.
- Plasma uses Wayland. Do not expose the Plasma X11 session.
- Hyprland always starts through UWSM.
- The Hyprland rice remains unchanged on workstation.
- Hyprland-only services stop when the Hyprland session stops.
- Adelie does not receive Steam, gamescope, virtualization, Sunshine, or the
  workstation application bundles.
- Adelie receives the complete desktop-settings authority because the existing
  rice depends on it.
- The desktop-settings authority derives the active host name. It does not
  identify every host as workstation.
- Plasma uses the KDE portal policy. Hyprland uses the Hyprland and GTK portal
  policy.
- Greetd unlocks GNOME Keyring and KWallet through PAM.
- NVIDIA DRM modesetting supplies local Wayland rendering on both hosts.
- Remote desktop is not part of this change.
- Deployment must not change DNS, routes, secrets, or public services.

## System composition

The profile graph has two levels:

```text
graphical-desktop
├── Hyprland + UWSM
├── Plasma
├── greetd session chooser
├── portals and keyrings
├── common audio
├── common desktop applications
├── fonts and Stylix
└── desktop-settings authority

workstation desktop
after graphical-desktop
├── gaming
├── virtualization
└── Sunshine
```

The shared login chooser exposes only these desktop files:

- `plasma.desktop`
- `hyprland-uwsm.desktop`

This filtered list makes the unsupported sessions unavailable. The raw
`hyprland.desktop` and `plasmax11.desktop` files remain outside the chooser.

## Home composition

The reusable Hyprland profile owns the rice and its session packages. The full
workstation desktop profile adds productivity, communication, research, audio,
and video applications.

Adelie imports the shared operator core and the reusable Hyprland profile. It
does not import `users/nori/home.nix` or `users/nori/workstation.nix`.

All rice services use `hyprland-session.target`. The resource monitor uses the
same target instead of `timers.target`. Plasma must not start or poll the rice
services.

## Hardware

Workstation keeps its existing RTX 5060 Ti policy.

Adelie changes from Nouveau to the production NVIDIA driver for its RTX 2060
Super. The configuration enables graphics, the open kernel module, and DRM
modesetting. A reboot is required before the new driver supplies the display.

The Adelie driver change does not grant GPU access to server workloads. The
`nori.gpu.nvidiaDevices` service capability remains a separate declaration.

## Acceptance gates

The repository change is complete when all gates pass:

1. Both host evaluations enable `programs.hyprland` and Plasma 6.
2. Greetd is enabled on both hosts. SDDM and Plasma Login Manager are disabled.
3. The login chooser contains only Plasma and UWSM Hyprland.
4. Adelie does not enable Steam, Sunshine, or libvirtd.
5. Both Home Manager evaluations enable the Hyprland rice.
6. Hyprland services and the resource monitor use `hyprland-session.target`.
7. The desktop-settings source marker names the evaluated host.
8. Both host closures build.
9. The workstation can log in to Plasma, then log in to Hyprland.
10. Adelie can log in to Plasma, then log in to Hyprland after its reboot.
11. The Plasma session has no active Hyprland rice services.
12. The Hyprland session starts the existing rice services.
13. Each session opens a file chooser and starts its selected portal backend.
14. Greetd unlocks KWallet and GNOME Keyring without a repeated login prompt.
15. Existing server services remain healthy after the Adelie reboot.

## Rollback

Remove the `graphical-desktop` profile from Adelie. Restore its prior hardware
configuration and reboot to return to Nouveau.

Remove Plasma and the filtered chooser from the shared profile to restore the
single Hyprland session. The workstation hardware and rice remain unchanged.
