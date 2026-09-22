# Peer remote desktop activation — September 22, 2026

## Scope

The initial activation used source revision `4f82f3a0d228ba0038f148c99c50654ca89eeefd`. Follow-up corrections ended with code revision `8961c9b`.

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

## Interactive peer acceptance

### Sunshine and Moonlight

Sunshine 2026.804.1201 crashed on Adelie after the RTSP `ANNOUNCE` request. Revision `62cf5e4` selected beta 2026.914.233613.

The beta package completed the same request. Revision `6c02121` also gave `nori` access to `/dev/uinput`.

Revision `b4e7e97` disabled the unsupported Sunshine tray. The tray blocked the end of a graphical session.

Moonlight paired in both directions with host-specific client certificates. Each client displayed the live peer desktop.

Remote key input changed the peer session in both directions. The client logs also showed Opus initialization.

This evidence does not prove audible output on physical speakers.

### RustDesk

The first Wayland share failed after portal selection. RustDesk could not create the GStreamer element `pipewiresrc`.

Revision `8961c9b` added PipeWire's GStreamer plugin directory to the RustDesk wrapper on both hosts.

The deployment planner selected Adelie before workstation for this correction.

| Host | Activation time | System closure |
|---|---|---|
| Adelie | 2026-09-22 21:22:56 UTC | `/nix/store/d75ic4g6dmr4jdzxzw923nzygcymid7r-nixos-system-adelie-26.11.20260920.44a9189` |
| workstation | 2026-09-22 21:26:12 UTC | `/nix/store/vsm0zn2abnghs484mhn3pvb4ink5b16a-nixos-system-workstation-26.11.20260920.44a9189` |

Both hosts reported `running` and zero failed units after activation. Both deployed RustDesk wrappers referenced the PipeWire plugin.

Adelie connected to workstation at `100.81.5.122:21118`. The session used a one-time credential, local acceptance, and portal selection.

Adelie displayed the live workstation desktop. The deployed wrapper provided `pipewiresrc` without a manual environment change.

Cleanup stopped the transient RustDesk processes. Neither host retained a TCP 21118 listener.

## Remaining physical acceptance

1. Connect from workstation to Adelie's direct-IP listener. Verify RustDesk video and remote input.
2. Verify RustDesk remote input from Adelie to workstation.
3. Verify audible Moonlight audio on the physical outputs.
4. At each greetd screen, log in to Plasma, Plasma Bigscreen, and Hyprland.
5. Verify the portal and one-password keyring path in each Plasma and Hyprland session.
6. Use a Moonlight television client to start Bigscreen and verify remote input.

This report does not prove reboot persistence, login-screen access, independent concurrent seats, or television compatibility.
