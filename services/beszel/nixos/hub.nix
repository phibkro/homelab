{ config, ... }:

let
  metrics = config.nori.inventory.routes.metrics;
in

{
  /**
    beszel-hub — central PocketBase + UI that pulls metrics from
    agents over tailnet. Lives on the appliance host (pi) so the
    hub survives station outages: when station hangs, the hub keeps
    recording its metrics up to the last poll, useful for post-incident
    forensics ("what was CPU/mem doing right before the freeze?").
    Migrated from station 2026-04-29 (commit b4499ee).

    The canonical metrics endpoint and Authelia client declaration live in
    manifests/hub.nix. PocketBase still requires the operator to paste the
    generated client secret into the users collection's OAuth2 settings;
    USER_CREATION=true lets the first OIDC login auto-provision while local
    password auth remains available as recovery.
  */

  services.beszel.hub = {
    enable = true;
    host = "0.0.0.0";
    inherit (metrics) port;
  };

  systemd.services.beszel-hub.environment = {
    USER_CREATION = "true";
  };

  nori.harden.beszel-hub = { };

  /*
    Gatus alerts come independently via ntfy.sh, so a hub rebuild
    loses only recent metrics history. Revisit when Pi gains the
    planned local fast-restore SSD repo (see services/restic-backup/nixos.nix L28).
  */
  nori.backups.beszel.skip = "Hub on appliance host. Pi flash anti-write posture + non-load-bearing metrics; defer until Pi local-fast-restore repo lands.";
}
