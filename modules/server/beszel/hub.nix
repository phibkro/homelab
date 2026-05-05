{
  config,
  lib,
  pkgs,
  ...
}:

{
  # beszel-hub — central PocketBase + UI that pulls metrics from
  # agents over tailnet. Lives on the appliance host (pi) so the
  # hub survives station outages: when station hangs, the hub keeps
  # recording its metrics up to the last poll, useful for post-incident
  # forensics ("what was CPU/mem doing right before the freeze?").
  # Migrated from station 2026-04-29 (commit b4499ee).
  #
  # Hub web UI on port 8090, surfaced to the LAN via the Caddy host's
  # reverse proxy as https://metrics.nori.lan (route declared in
  # ./agent.nix gated on Caddy presence — only registers where Caddy
  # actually runs).
  #
  # OIDC SSO via Authelia is deferred — hub-side OAuth wiring not yet
  # plumbed. USER_CREATION=true is set in advance so first OIDC login
  # auto-provisions; DISABLE_PASSWORD_AUTH stays off, keeping the
  # local-password fallback as recovery.

  services.beszel.hub = {
    enable = true;
    host = "0.0.0.0";
    port = 8090;
  };

  systemd.services.beszel-hub.environment = {
    USER_CREATION = "true";
  };

  nori.harden.beszel-hub = { };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8090 ];

  # Pi's storage posture is anti-write (no swap, volatile journald —
  # see hosts/pi/hardware.nix); daily restic snapshots to the
  # SD/FIT contradict that. The data itself is metrics — non-load-
  # bearing. Gatus alerts come independently via ntfy.sh; rebuilding
  # the hub from zero loses recent metrics history, that's it.
  # Revisit when Pi gains the planned local fast-restore SSD repo
  # (see modules/server/backup/restic.nix L28).
  nori.backups.beszel.skip = "Hub on appliance host. Pi flash anti-write posture + non-load-bearing metrics; defer until Pi local-fast-restore repo lands.";
}
