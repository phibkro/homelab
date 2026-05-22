# Sunshine remote-desktop host (workstation) + Moonlight client (MacBook)

**Date:** 2026-05-22
**Status:** Approved design, pending implementation plan

## Goal

Stream the workstation's live Hyprland session to the MacBook over the
tailnet, low-latency, so DaVinci Resolve can be edited remotely. The
workstation (NVIDIA GPU) does all the work; the MacBook is a thin client.

This is remote-desktop (screen sharing), **not** a Resolve feature —
Resolve free is unaffected and unaware. It is explicitly not a render
farm (Studio-only) and not Resolve's PostgreSQL project-database
collaboration.

## Operational model (scenario "a")

- Physical monitor stays **on**; Sunshine captures the real display.
- Log in at the console **once per boot** (greetd → Hyprland). Sunshine
  is a systemd *user* unit and needs a running graphical session; the
  greetd login prompt is not a session it can attach to.
- Lock with hyprlock when stepping away (do **not** log out — a locked
  session is still running). Moonlight in, type the password over the
  stream to unlock.
- **Accepted limitation:** a reboot-while-away lands at greetd with no
  session → remotely locked out until a physical login. No autologin.
- **Privacy note:** single-display capture mirrors the live session to
  the physical monitor — anyone at the machine sees the remote session.

## Host: workstation (Sunshine)

New module `modules/desktop/sunshine.nix`, imported via
`modules/desktop/default.nix`. `modules/desktop/` is Linux/Hyprland-only
and is **not** imported by the darwin MacBook (it imports only
`../pc.nix`), so Sunshine is workstation-only by construction.

Config:

- `services.sunshine.enable = true`
- `package = pkgs.sunshine.override { cudaSupport = true; }` — **NVENC**
  hardware encode on the NVIDIA GPU. Pulls CUDA (large closure);
  `allowUnfree` is already enabled for davinci-resolve.
- `capSysAdmin = true` — **KMS capture** (Approach 1). The usual
  downside (apps *launched by* Sunshine run as root) does not apply:
  we stream the already-running desktop via Sunshine's built-in
  "Desktop" entry, which launches nothing.
- `autoStart = true` — systemd user unit starts on graphical login.
- `openFirewall = false`.

Networking (mirrors the beszel/ntfy/samba pattern — nothing on LAN/WAN):
open Sunshine's port set **only on `tailscale0`** via
`networking.firewall.interfaces."tailscale0"`. Port list is mirrored
from the module's own `openFirewall` definition at implementation time
to avoid drift; expected set:

- TCP: 47984, 47989, 47990 (web UI), 48010
- UDP: 47998, 47999, 48000, 48002

Audio: Sunshine's PipeWire virtual sink (default) streams timeline audio
to the client.

Backup intent: stateless service config; declare
`nori.backups.sunshine.skip` per repo convention (pairing state lives in
`~/.config/sunshine`, re-pairable; not worth backing up).

## Client: MacBook (Moonlight)

MacBook handles Darwin GUI apps via Homebrew casks (ghostty, utm,
handbrake precedent). Moonlight follows the same pattern:

- **Homebrew cask** (`brew install --cask moonlight`), documented inline
  in `machines/macbook/home.nix` matching the ghostty/handbrake/utm
  comment style. Not `pkgs.moonlight-qt`.

## Pairing (one-time)

1. Browse `https://workstation:47990` over the tailnet.
2. Set Sunshine admin credentials on first run.
3. Moonlight discovers the host (or add by tailnet hostname/IP); enter
   the PIN shown by Moonlight into the Sunshine web UI.

## Known risk + verification

Main risk: NVIDIA Wayland KMS capture can black-screen. Verify:

1. `systemctl --user status sunshine` is active on the workstation.
2. Web UI reachable from the MacBook over the tailnet (`:47990`).
3. A real Moonlight session shows the live desktop **and** audio.

Fallback if it black-screens: Approach 2 (wlroots/`wlr` capture without
`capSysAdmin`), or tuning capture env vars.

## Out of scope

Headless/virtual-display (scenario b), autologin, multi-monitor, HDR,
render-farm / Studio network rendering, Resolve PostgreSQL project DB.
