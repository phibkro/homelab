{ config, lib, pkgs, ... }:

{
  # Uptime Kuma — synthetic HTTP/TCP/DNS uptime checks. Probes
  # services from the outside (the hub's perspective), catches
  # "the daemon is up but the HTTP handler is returning 500" cases
  # that beszel can't see. Per DESIGN.md L457.
  #
  # First-time setup after activation:
  #   1. Connect to http://nori-station.saola-matrix.ts.net:3001
  #   2. Create admin user (form on first connect)
  #   3. Add monitors for the live tailnet services:
  #        - Open WebUI:  GET http://nori-station.saola-matrix.ts.net:8080
  #        - Jellyfin:    GET http://nori-station.saola-matrix.ts.net:8096
  #        - Ollama:      GET http://nori-station.saola-matrix.ts.net:11434/api/tags
  #        - Blocky:      DNS (manual config) or HTTP probe
  #   4. Settings → Notifications → ntfy → URL https://ntfy.sh/<channel>
  #      with appropriate priority (urgent for service down). Same
  #      channel as the OnFailure template in ntfy.nix.
  #
  # DESIGN noted "container (no native module yet)" — the
  # `services.uptime-kuma` NixOS module landed since then. Native
  # module is preferred over a container.
  #
  # State (sqlite db, monitor configs) at /var/lib/uptime-kuma.

  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = "0.0.0.0";
      PORT = "3001";
    };
  };

  systemd.services.uptime-kuma.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
    BindReadOnlyPaths = [ ];
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 3001 ];
}
