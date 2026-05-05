# The "server" concern — every module a host needs to *serve*
# things to other devices: HTTPS reverse proxy, DNS, SSO, monitoring,
# media servers, password manager, alerts, *arr stack, backups, …
#
# Hosts compose by adding `../../modules/server` to their `imports`
# alongside `../../modules/common` (universal) and optionally
# `../../modules/desktop` (graphical session). A host that includes
# this concern is a server; one that omits it isn't. Reading the
# host file should answer "what kind of machine is this?" at a glance.
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
#
# Every server host today imports this whole concern as one block
# (only workstation serves at the moment). When a second server
# arrives that runs a subset (e.g. pi → DNS + restic-target,
# no Immich/*arr/Vaultwarden), this file gets refactored into
# sub-concerns the host can pick from. Defer until the second host
# actually exists.
_: {
  imports = [
    # Coupled stacks (folder = coupling)
    ./arr
    ./backup

    # Loose services
    ./authelia.nix
    ./beszel/agent.nix
    ./blocky.nix
    ./caddy.nix
    ./calibre-web.nix
    ./filmder.nix
    ./finnbydel.nix
    ./gatus.nix
    ./glance.nix
    ./immich.nix
    ./jellyfin.nix
    ./komga.nix
    ./navidrome.nix
    ./ntfy/notify.nix
    ./ollama.nix
    ./open-webui.nix
    ./radicale.nix
    ./samba.nix
    ./syncthing.nix
    ./vaultwarden.nix
  ];
}
