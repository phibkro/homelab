{ config, pkgs, ... }:
let
  # Nixpkgs PR #533497: maintainer-approved Sunshine update. Stable 2026.516
  # stalls Linux RTSP ANNOUNCE, so Moonlight never receives the session reply.
  sunshineNixpkgs = builtins.fetchTree {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "306e7f543163b37249a7c546ccd4551a4eb8f4df";
    narHash = "sha256-Fa1BtrZoi6rUUK+bMkUFDCQIudIppVgupMy3Je6SWQ8=";
  };
  sunshine = pkgs.callPackage "${sunshineNixpkgs}/pkgs/by-name/su/sunshine/package.nix" { };
in
{
  /*
    Sunshine — game-stream host for remote desktop over the tailnet.
    Moonlight connects to drive either graphical host's live Wayland session.
    The host GPU does all encode/render work; the client is thin.

    Shared by construction through the graphical-desktop profile. Runtime
    pairing and credentials remain per-user mutable state.
    Contract: docs/specs/2026-09-22-peer-remote-desktops.md.
  */
  services.sunshine = {
    enable = true;

    /*
      NVENC hardware encode on the NVIDIA GPU. cudaSupport pulls CUDA
      (large closure; unfree, already permitted for davinci-resolve).
      Without it Sunshine falls back to CPU x264 — high latency + load.
    */
    package = sunshine.override { cudaSupport = true; };

    /*
      CAP_SYS_ADMIN for DRM/KMS screen capture — the reliable path on
      NVIDIA + Wayland (the module adds a setuid-capability wrapper).
      The usual caveat (apps launched *by* Sunshine run as root) does
      not apply: we stream the already-running desktop via Sunshine's
      built-in "Desktop" entry, which launches nothing. If capture
      black-screens, fall back to wlr capture (capSysAdmin = false) —
      Hyprland is wlroots-based.
    */
    capSysAdmin = true;

    /*
      systemd user unit started with graphical-session.target. Needs a logged-in
      graphical session — the greetd prompt is not a session it can attach to.
      A second simultaneous user instance would contend for ports.
    */
    autoStart = true;

    # Ports scoped to tailscale0 below, not opened on all interfaces.
    openFirewall = false;
    settings.csrf_allowed_origins = "https://${config.networking.hostName}.saola-matrix.ts.net:47990";
  };

  # Virtual pointer and keyboard injection uses /dev/uinput.
  users.users.nori.extraGroups = [ "uinput" ];

  # Moonlight peers are added explicitly by tailnet name; publish no LAN mDNS.
  services.avahi.enable = false;

  /*
    Tailnet-only exposure — mirrors the beszel/ntfy/samba pattern;
    nothing on LAN/WAN. Ports are Sunshine's default base port (47989)
    plus the module's own offsets: TCP {-5,0,1,21}, UDP {9,10,11,13,21}.
    Hardcoded here because openFirewall = false; keep in sync if the
    base port is ever changed via services.sunshine.settings.port.
  */
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      47984
      47989
      47990 # Sunshine web UI (pairing/config)
      48010
    ];
    allowedUDPPorts = [
      47998
      47999
      48000
      48002
      48010
    ];
  };
}
