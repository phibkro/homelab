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
// {
  calibre-web = import ../modules/services/calibre-web/manifest.nix;
  filmder = import ../modules/services/filmder/manifest.nix;
  glance = import ../modules/services/glance/manifest.nix;
  grafana = import ../modules/infra/observability/grafana/manifest.nix;
  heim = import ../modules/services/heim/manifest.nix;
  immich = import ../modules/services/immich/manifest.nix;
  jellyfin = import ../modules/services/jellyfin/manifest.nix;
  komga = import ../modules/services/komga/manifest.nix;
  miniflux = import ../modules/services/miniflux/manifest.nix;
  navidrome = import ../modules/services/navidrome/manifest.nix;
  ollama = import ../modules/services/ollama/manifest.nix;
  open-webui = import ../modules/services/open-webui/manifest.nix;
  paperless = import ../modules/services/paperless/manifest.nix;
  radicale = import ../modules/services/radicale/manifest.nix;
  stremio = import ../modules/services/stremio/manifest.nix;
  suwayomi = import ../modules/services/suwayomi/manifest.nix;
  vaultwarden = import ../modules/services/vaultwarden/manifest.nix;
}
