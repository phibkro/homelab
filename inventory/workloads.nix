/*
  Stable workload identifiers known to the homelab inventory compiler.

  Every identifier is aggregated explicitly with its pure manifest below.
  Keeping the catalog explicit makes profile/host references fail before NixOS
  module evaluation and prevents directory names or tags from becoming hidden
  deployment behavior.
*/
_:

{
  authelia = import ../services/authelia/manifest.nix;
  attic = import ../services/attic/manifest.nix;
  bazarr = import ../services/bazarr/manifest.nix;
  beszel-agent = import ../services/beszel/manifests/agent.nix;
  beszel-hub = import ../services/beszel/manifests/hub.nix;
  pihole = import ../services/pihole/manifest.nix;
  caddy = import ../services/caddy/manifest.nix;
  calibre-web = import ../services/calibre-web/manifest.nix;
  clamor = import ../services/clamor/manifest.nix;
  cloudflare-ddns = import ../services/cloudflare-ddns/manifest.nix;
  disk-alert = import ../services/disk-alert/manifest.nix;
  filmder = import ../services/filmder/manifest.nix;
  gatus = import ../services/gatus/manifest.nix;
  glance = import ../services/glance/manifest.nix;
  grafana = import ../services/grafana/manifest.nix;
  heartbeat = import ../services/heartbeat/manifest.nix;
  heim = import ../services/heim/manifest.nix;
  herdr-projects-mcp = import ../services/herdr-projects-mcp/manifest.nix;
  hindsight = import ../services/hindsight/manifest.nix;
  immich = import ../services/immich/manifest.nix;
  jellyfin = import ../services/jellyfin/manifest.nix;
  jellyseerr = import ../services/jellyseerr/manifest.nix;
  komga = import ../services/komga/manifest.nix;
  lidarr = import ../services/lidarr/manifest.nix;
  mcp-origin-tunnel = import ../services/mcp-origin-tunnel/manifest.nix;
  miniflux = import ../services/miniflux/manifest.nix;
  music-ingest = import ../services/music-ingest/manifest.nix;
  navidrome = import ../services/navidrome/manifest.nix;
  node-exporter = import ../services/node-exporter/manifest.nix;
  nvidia-gpu-exporter = import ../services/nvidia-gpu-exporter/manifest.nix;
  ntfy-server = import ../services/ntfy/manifests/server.nix;
  ntfy-notify = import ../services/ntfy/manifests/notify.nix;
  ollama = import ../services/ollama/manifest.nix;
  open-webui = import ../services/open-webui/manifest.nix;
  paperless = import ../services/paperless/manifest.nix;
  prowlarr = import ../services/prowlarr/manifest.nix;
  qbittorrent = import ../services/qbittorrent/manifest.nix;
  radarr = import ../services/radarr/manifest.nix;
  radicale = import ../services/radicale/manifest.nix;
  restic-target = import ../services/restic-target/manifest.nix;
  recyclarr = import ../services/recyclarr/manifest.nix;
  samba = import ../services/samba/manifest.nix;
  sonarr = import ../services/sonarr/manifest.nix;
  stremio = import ../services/stremio/manifest.nix;
  suwayomi = import ../services/suwayomi/manifest.nix;
  syncthing = import ../services/syncthing/manifest.nix;
  vaultwarden = import ../services/vaultwarden/manifest.nix;
  victorialogs-server = import ../services/victorialogs/manifest.nix;
  victoriametrics = import ../services/victoriametrics/manifest.nix;
}
