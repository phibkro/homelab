/**
  The "services" concern — every service module the homelab might
  run on any host: HTTPS reverse proxy, DNS, SSO, monitoring, media
  servers, password manager, alerts, *arr stack, backups, …

  Importing this bundle gives the host the full route registry +
  option schemas. Activation is per-service via
  `nori.services.<X>.enable` (or `nori.enableServicesByTag = [ ... ]`)
  — three of the four NixOS hosts (pi, aurora, workstation) import
  the bundle today, each activating a different subset. Pavilion
  flat-imports only what it needs (no LAN services).

  Migration boundary: catalog/runtime-split workloads are absent from this
  legacy bundle. Their manifests are globally visible through
  `nori.inventory`, their routes project from the pure inventory, and their
  runtime modules are selected only for placement hosts by the machine
  factory. Jellyfin is the first vertical pilot. Unmigrated workloads still
  declare routes outside their activation gate so bundle-importing entry-plane
  hosts can see them.

  Tightly-coupled stacks live under their own folders:
    arr/      — Sonarr/Radarr/Lidarr/Bazarr/Jellyseerr/Prowlarr/qBittorrent.
                Cross-reference each other via API + share /mnt/media/
                streaming via the `media` group + arr-internal tmpfiles.
                Inventory identities select one shared runtime module.
    backup/   — restic + verify (drill) + btrbk. Share /mnt/backup, the
                restic-password sops secret, and the notify@ pipeline.

  Loose services that just happen to be in the same conceptual zone
  stay flat at the top level (one file per service). Folders signal
  coupling, not categorization.
*/
_: {
  imports = [
    # Legacy loose services; migrated services are inventory-selected.
    ./music-ingest.nix
    ./papers-fetch.nix
  ];
}
