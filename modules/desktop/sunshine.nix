{ pkgs, ... }:
{
  # Sunshine — game-stream host for remote desktop over the tailnet.
  # Moonlight (MacBook) connects to drive the workstation's live
  # Hyprland session, primarily for remote DaVinci Resolve editing; the
  # GPU does all encode/render work, the client is thin.
  #
  # Workstation-only by construction: imported via
  # modules/desktop/default.nix, which the darwin MacBook never imports
  # (it pulls only ../pc.nix). Design + rationale:
  # docs/superpowers/specs/2026-05-22-sunshine-remote-host-design.md.
  services.sunshine = {
    enable = true;

    # NVENC hardware encode on the NVIDIA GPU. cudaSupport pulls CUDA
    # (large closure; unfree, already permitted for davinci-resolve).
    # Without it Sunshine falls back to CPU x264 — high latency + load.
    package = pkgs.sunshine.override { cudaSupport = true; };

    # CAP_SYS_ADMIN for DRM/KMS screen capture — the reliable path on
    # NVIDIA + Wayland (the module adds a setuid-capability wrapper).
    # The usual caveat (apps launched *by* Sunshine run as root) does
    # not apply: we stream the already-running desktop via Sunshine's
    # built-in "Desktop" entry, which launches nothing. If capture
    # black-screens, fall back to wlr capture (capSysAdmin = false) —
    # Hyprland is wlroots-based.
    capSysAdmin = true;

    # systemd user unit started with graphical-session.target. Needs a
    # logged-in Hyprland session — the greetd prompt is not a session it
    # can attach to (scenario "a": log in once per boot).
    autoStart = true;

    # Ports scoped to tailscale0 below, not opened on all interfaces.
    openFirewall = false;
  };

  # Tailnet-only exposure — mirrors the beszel/ntfy/samba pattern;
  # nothing on LAN/WAN. Ports are Sunshine's default base port (47989)
  # plus the module's own offsets: TCP {-5,0,1,21}, UDP {9,10,11,13,21}.
  # Hardcoded here because openFirewall = false; keep in sync if the
  # base port is ever changed via services.sunshine.settings.port.
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
