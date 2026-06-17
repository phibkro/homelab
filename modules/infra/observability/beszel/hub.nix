{ config, lib, ... }:

lib.mkMerge [
  {
    nori.services.beszel-hub.tags = [
      "observability"
      "stateful"
    ];
  }
  (lib.mkIf config.nori.services.beszel-hub.enabled {
    /**
      beszel-hub — central PocketBase + UI that pulls metrics from
      agents over tailnet. Lives on the appliance host (pi) so the
      hub survives station outages: when station hangs, the hub keeps
      recording its metrics up to the last poll, useful for post-incident
      forensics ("what was CPU/mem doing right before the freeze?").
      Migrated from station 2026-04-29 (commit b4499ee).

      https://metrics.nori.lan vhost is declared in ./agent.nix (gated
      on Caddy presence so Pi doesn't try to proxy to itself).

      OIDC SSO via Authelia is deferred — hub-side OAuth wiring not yet
      plumbed. USER_CREATION=true is set in advance so first OIDC login
      auto-provisions; DISABLE_PASSWORD_AUTH stays off, keeping the
      local-password fallback as recovery.
    */

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

    /*
      Gatus alerts come independently via ntfy.sh, so a hub rebuild
      loses only recent metrics history. Revisit when Pi gains the
      planned local fast-restore SSD repo (see modules/infra/backup/restic.nix L28).
    */
    nori.backups.beszel.skip = "Hub on appliance host. Pi flash anti-write posture + non-load-bearing metrics; defer until Pi local-fast-restore repo lands.";
  })
]
