/*
  Stable workload identifiers known to the homelab inventory compiler.

  Every identifier is aggregated explicitly with its pure manifest below.
  Each manifest owns its ordered placement selectors. Keeping the catalog
  explicit makes missing declarations fail before NixOS module evaluation.
*/
_:
let
  manifest = path: (import path) // { _manifestPath = path; };
in
{
  authelia = manifest ../services/authelia/manifest.nix;
  attic = manifest ../services/attic/manifest.nix;
  attic-publisher = manifest ../services/attic-publisher/manifest.nix;
  bazarr = manifest ../services/bazarr/manifest.nix;
  beszel-agent = manifest ../services/beszel/manifests/agent.nix;
  beszel-hub = manifest ../services/beszel/manifests/hub.nix;
  pihole = manifest ../services/pihole/manifest.nix;
  caddy = manifest ../services/caddy/manifest.nix;
  calibre-web = manifest ../services/calibre-web/manifest.nix;
  cloudflare-ddns = manifest ../services/cloudflare-ddns/manifest.nix;
  disk-alert = manifest ../services/disk-alert/manifest.nix;
  gatus = manifest ../services/gatus/manifest.nix;
  glance = manifest ../services/glance/manifest.nix;
  grafana = manifest ../services/grafana/manifest.nix;
  heartbeat = manifest ../services/heartbeat/manifest.nix;
  herdr-projects-mcp = manifest ../services/herdr-projects-mcp/manifest.nix;
  hindsight = manifest ../services/hindsight/manifest.nix;
  immich = manifest ../services/immich/manifest.nix;
  jellyfin = manifest ../services/jellyfin/manifest.nix;
  jellyseerr = manifest ../services/jellyseerr/manifest.nix;
  komga = manifest ../services/komga/manifest.nix;
  lidarr = manifest ../services/lidarr/manifest.nix;
  mcp-origin-tunnel = manifest ../services/mcp-origin-tunnel/manifest.nix;
  miniflux = manifest ../services/miniflux/manifest.nix;
  music-ingest = manifest ../services/music-ingest/manifest.nix;
  navidrome = manifest ../services/navidrome/manifest.nix;
  node-exporter = manifest ../services/node-exporter/manifest.nix;
  nvidia-gpu-exporter = manifest ../services/nvidia-gpu-exporter/manifest.nix;
  ntfy-server = manifest ../services/ntfy/manifests/server.nix;
  ntfy-notify = manifest ../services/ntfy/manifests/notify.nix;
  ollama = manifest ../services/ollama/manifest.nix;
  open-webui = manifest ../services/open-webui/manifest.nix;
  paperless = manifest ../services/paperless/manifest.nix;
  prowlarr = manifest ../services/prowlarr/manifest.nix;
  qbittorrent = manifest ../services/qbittorrent/manifest.nix;
  radarr = manifest ../services/radarr/manifest.nix;
  radicale = manifest ../services/radicale/manifest.nix;
  restic-target = manifest ../services/restic-target/manifest.nix;
  recyclarr = manifest ../services/recyclarr/manifest.nix;
  samba = manifest ../services/samba/manifest.nix;
  sonarr = manifest ../services/sonarr/manifest.nix;
  stremio = manifest ../services/stremio/manifest.nix;
  suwayomi = manifest ../services/suwayomi/manifest.nix;
  syncthing = manifest ../services/syncthing/manifest.nix;
  vaultwarden = manifest ../services/vaultwarden/manifest.nix;
  victorialogs-server = manifest ../services/victorialogs/manifest.nix;
  victoriametrics = manifest ../services/victoriametrics/manifest.nix;
}
