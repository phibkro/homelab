---
summary: Symmetric tailnet remote-desktop clients, hosts, and TV sessions on workstation and Adelie.
date: 2026-09-22
status: accepted — governing design for feat/dual-desktop-sessions
owner: operator
implementation_branch: feat/dual-desktop-sessions
---

# Peer remote desktops

## Problem

Workstation and Adelie both provide local Plasma and Hyprland sessions, but their remote-desktop capabilities are asymmetric. Workstation alone hosts Sunshine, neither host declares Moonlight, RustDesk is only an unconfigured client package, and Plasma Bigscreen is absent from the filtered greetd chooser.

## Goal

Make each host a peer that can initiate or receive an interactive remote-desktop connection over the tailnet and can launch Plasma Bigscreen as a local Wayland session.

## Constraints

- Remote listeners are reachable only through `tailscale0`.
- No service opens remote-desktop ports globally or on the LAN.
- RustDesk, Moonlight, and Plasma Bigscreen are available on both hosts.
- RustDesk's direct-IP TCP port is admitted only on `tailscale0`; enabling the
  listener and setting its access password remain explicit operator actions.
- Sunshine is enabled on both hosts with NVIDIA hardware encoding and existing-session capture.
- Plasma Bigscreen joins the existing filtered greetd chooser; greetd remains the only display manager.
- Pairing credentials, permanent access passwords, and first-use portal grants remain operator-owned runtime state.
- Both hosts derive the `nori` console password from one shared SOPS secret.
- The implementation does not claim headless login, virtual displays, independent concurrent Wayland seats, or access to the greeter.
- Existing local Plasma and Hyprland sessions remain available.

## Observable contract

1. Both evaluated host configurations enable Sunshine.
2. Both host firewalls expose only Sunshine's declared TCP and UDP ports on `tailscale0`.
3. Both Home Manager configurations install RustDesk and Moonlight.
4. The filtered greetd chooser exposes exactly Plasma, UWSM Hyprland, and Plasma Bigscreen Wayland.
5. Both host firewalls admit RustDesk's default direct-IP TCP port 21118 only
   on `tailscale0`; neither host opens RustDesk or Sunshine ports globally.
6. Both hosts derive the `nori` console password from one encrypted SOPS hash.
7. Both exact host closures build.
8. After activation and a graphical login, each host can reach the other host's Sunshine listener through its tailnet hostname.
9. Operator pairing proves one real streamed desktop and input path in each direction; Bigscreen appearance, audio, capture, and TV-client behavior remain physical acceptance evidence.

## Security model

Tailscale membership and ACLs gate network reachability. Sunshine retains its own pairing and administrative credentials. RustDesk must not silently depend on public rendezvous infrastructure for the accepted direct-peer path; direct-IP access, credentials, and any required listener are explicit. Remote users control the currently logged-in graphical session and inherit that user's authority.

## Non-goals

- Multi-user RDP or disposable desktops.
- Concurrent independent Wayland compositors on one physical seat.
- Public Internet listeners.
- Automatic credential generation or secret publication.
- Replacing Jellyfin or native TV applications for ordinary media playback.

## Acceptance boundaries

Evaluation and closure builds prove configuration. Read-only socket and HTTP probes after activation prove peer reachability. They do not prove video capture, audio, remote input, TV decoder behavior, login-screen access, or operator credentials. Those require an active graphical session and explicit operator pairing.
