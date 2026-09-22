# Dual desktop activation — September 22, 2026

## Scope

This activation deployed Plasma and UWSM Hyprland as local session choices on
workstation and Adelie. It did not change DNS, routes, secrets, or public
services.

The source branch was `feat/dual-desktop-sessions`. The accepted contract is
`docs/specs/2026-09-22-dual-desktop-sessions.md`.

## Repository evidence

The `eval-dual-desktop-sessions` check passed. It verifies these properties:

- Both hosts enable Plasma, Hyprland, and greetd.
- SDDM and Plasma Login Manager remain disabled.
- The immutable greetd chooser contains only `plasma.desktop` and
  `hyprland-uwsm.desktop`.
- Adelie does not gain workstation-only gaming, virtualization, or Sunshine
  services.
- Both Home Manager configurations enable the Hyprland rice.
- Hyprland-only services use `hyprland-session.target`.
- The desktop-settings source marker names the evaluated host.

Both system closures built:

- Adelie: `/nix/store/frpa38g0jvwdi4kj1fs9zcqrl1nrnpzp-nixos-system-adelie-26.11.20260910.8ce4ef6`
- workstation: `/nix/store/hvbmdcb0dqpx123mdxyips1h3kzfdb20-nixos-system-workstation-26.11.20260910.8ce4ef6`

The deployment planner selected Adelie before workstation. Dry activation on
both hosts showed the expected greetd, Home Manager, and device changes.

## Activated state

Adelie and workstation activated the built closures in planner order.

Adelie then rebooted. The following post-reboot checks passed:

- `systemctl is-system-running --wait` returned `running`.
- greetd, Home Manager, Attic, and the Beszel agent were active.
- The chooser contained only Plasma and UWSM Hyprland.
- The NVIDIA open kernel modules loaded at version `595.99.02`.
- DRM modesetting was active for the RTX 2060 Super.
- `nvidia-smi` reported the RTX 2060 Super and an active display.

The first Adelie boot entered `degraded` state because a restored
`user-1000.journal` file had group `root` instead of `systemd-journal`.
Changing only that file's group and restarting `systemd-journal-flush.service`
returned the host to `running`. `journalctl --verify` passed before the repair.
No repository configuration caused or required this ownership correction.

Workstation remained in its active Hyprland session during activation. A
nested Plasma Wayland session then started on the live Hyprland compositor.
KWin, Plasma Shell, KDE and GTK portals, KWallet portal support, and the Plasma
panel started. A captured frame showed the rendered Plasma desktop. Stopping
the nested session left the Hyprland compositor and Waybar active. Running the
new `hyprctl` with a clean environment confirmed the compositor still served
monitors and clients.

## Remaining physical acceptance

The deployment does not prove authenticated local session switching. A remote
transient-login attempt on Adelie stopped at PAM and was removed without
changing authentication. The following gates still require the operator at
each local console:

1. Log in to Plasma, then log out.
2. Log in to Hyprland, then log out.
3. Open a file chooser in each session and confirm the selected portal.
4. Confirm that KWallet and GNOME Keyring do not request the login password a
   second time.
5. Confirm that Hyprland rice services are absent in Plasma and active in
   Hyprland.

These gates remain in `docs/roadmap.md` under Operator IOUs. The deployed
configuration is available now; only the physical acceptance evidence remains.
