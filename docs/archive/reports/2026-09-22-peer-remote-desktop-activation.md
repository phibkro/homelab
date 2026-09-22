# Peer remote desktop activation — September 22, 2026

## Scope

This activation applied the peer remote desktop contract to Adelie and workstation. The deployed source revision was `4f82f3a0d228ba0038f148c99c50654ca89eeefd`.

The configuration adds these functions to both hosts:

- Sunshine with NVIDIA encoding and a graphical-session user service.
- Moonlight and RustDesk clients.
- A tailnet-only firewall rule for RustDesk direct-IP TCP port 21118.
- Plasma Bigscreen in the filtered greetd session list.
- No Avahi service publication.

The activation did not change DNS, Cloudflare, secrets, or public services.

## Deployment

The deployment planner selected Adelie before workstation.

| Host | Activation time | System closure |
|---|---|---|
| Adelie | 2026-09-22 15:28:37 UTC | `/nix/store/4k1z73vb40w1vl4gr1axdw75nxq9p3c5-nixos-system-adelie-26.11.20260920.44a9189` |
| workstation | 2026-09-22 15:31:34 UTC | `/nix/store/7zwi0kjwvkqfqdahh9ar5mzl5392rx9w-nixos-system-workstation-26.11.20260920.44a9189` |

The Adelie activation restarted systemd, SSH, Tailscale, PostgreSQL, and the application services. The host returned to the `running` state.

The workstation activation restarted Home Manager. It also removed the unused Avahi service account and service.

## Runtime evidence

Both hosts reported `running`. Neither host had a failed systemd unit.

Adelie reported all selected service units as active. This set included SSH, Tailscale, PostgreSQL, Attic, Grafana, Miniflux, Radicale, Stremio, Vaultwarden, Beszel, and Prometheus.

Both greetd session lists contained exactly these files:

- `hyprland-uwsm.desktop`
- `plasma-bigscreen-wayland.desktop`
- `plasma.desktop`

Both hosts supplied the `moonlight`, `rustdesk`, and `plasma-bigscreen-wayland` programs.

The workstation Sunshine user service remained active after activation. Its HTTPS interface returned HTTP 401 at `https://127.0.0.1:47990/`.

Adelie reached the workstation Sunshine interface through the workstation tailnet name. The interface returned HTTP 401.

Adelie did not reach the same interface through the workstation LAN address. The LAN request reached its three-second timeout.

Tailscale ping worked in both directions. Adelie did not have an active Sunshine listener because Adelie had no active graphical login.

## Open physical acceptance

RustDesk direct-IP mode remains disabled runtime state. Workstation has no `direct-server` option, and Adelie has no RustDesk configuration file.

Neither host had a TCP 21118 listener. The operator must enable direct-IP mode and set credentials in each RustDesk session.

The following evidence still requires an active local session on Adelie:

1. Start Sunshine through a graphical login.
2. Pair Moonlight in each direction.
3. Prove video, audio, and remote input.
4. Connect RustDesk directly in each direction through the tailnet.
5. Open Plasma Bigscreen and prove the television input path.
6. Prove the Plasma and Hyprland portal and keyring paths.

This report does not prove reboot persistence, login-screen access, independent concurrent seats, or television compatibility.
