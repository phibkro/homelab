/*
  Stable workload identifiers known to the homelab inventory compiler.

  Phase 1 carries identity only. Catalog metadata and runtime-module handles
  move here incrementally during the vertical workload migration; keeping the
  identifiers explicit now lets profile/host references fail before NixOS
  module evaluation instead of becoming silent strings.
*/
{ lib }:

lib.genAttrs
  [
    "authelia"
    "bazarr"
    "beszel-agent"
    "beszel-hub"
    "blocky"
    "btrbk-replica-target"
    "btrbk-replication"
    "caddy"
    "calibre-web"
    "disk-alert"
    "filmder"
    "gatus"
    "glance"
    "grafana"
    "heartbeat"
    "heim"
    "immich"
    "jellyfin"
    "jellyseerr"
    "komga"
    "lidarr"
    "miniflux"
    "navidrome"
    "node-exporter"
    "ntfy-notify"
    "ntfy-server"
    "nvidia-gpu-exporter"
    "ollama"
    "open-webui"
    "paperless"
    "prowlarr"
    "qbittorrent"
    "radarr"
    "radicale"
    "recyclarr"
    "restic-target"
    "samba"
    "sonarr"
    "stremio"
    "suwayomi"
    "syncthing"
    "vaultwarden"
    "victorialogs-server"
    "victoriametrics"
  ]
  (_: {
    kind = "service";
  })
