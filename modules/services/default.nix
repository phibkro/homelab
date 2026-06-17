# The "services" concern — every service module the homelab might
# run on any host: HTTPS reverse proxy, DNS, SSO, monitoring, media
# servers, password manager, alerts, *arr stack, backups, …
#
# Importing this bundle gives the host the full route registry +
# option schemas. Activation is per-service via
# `nori.services.<X>.enable` (or `nori.enableServicesByTag = [ ... ]`)
# — three of the four NixOS hosts (pi, aurora, workstation) import
# the bundle today, each activating a different subset. Pavilion
# flat-imports only what it needs (no LAN services).
#
# Routes live OUTSIDE the per-service activation gate (in the first
# `mkMerge` block of each module), so every host that imports the
# bundle sees the route in `nori.lanRoutes` and can serve it via its
# Caddy. `runsOn` resolves the backend to the right host per route.
#
# Tightly-coupled stacks live under their own folders (each with a
# `default.nix` that imports siblings):
#   arr/      — Sonarr/Radarr/Lidarr/Bazarr/Jellyseerr/Prowlarr/qBittorrent.
#               Cross-reference each other via API + share /mnt/media/
#               streaming via the `media` group + arr-internal tmpfiles.
#   backup/   — restic + verify (drill) + btrbk. Share /mnt/backup, the
#               restic-password sops secret, and the notify@ pipeline.
#
# Loose services that just happen to be in the same conceptual zone
# stay flat at the top level (one file per service). Folders signal
# coupling, not categorization.
_: {
  imports = [
    # Coupled stacks (folder = coupling)
    ./arr

    # Loose services
    ./beszel/agent.nix
    ./calibre-web.nix
    ./disk-alert.nix
    ./filmder.nix
    ./gatus.nix
    ./glance.nix
    ./grafana.nix
    ./heim.nix
    ./hermes.nix
    ./immich.nix
    ./jellyfin.nix
    ./komga.nix
    ./miniflux.nix
    ./navidrome.nix
    ./node-exporter.nix
    ./nvidia-gpu-exporter.nix
    ./ntfy/notify.nix
    ./ollama.nix
    ./open-webui.nix
    ./radicale.nix
    ./samba.nix
    ./stremio.nix
    ./syncthing.nix
    ./vaultwarden.nix
    ./victorialogs/default.nix
  ];
}
