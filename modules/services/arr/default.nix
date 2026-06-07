# *arr stack — coupled cluster. These services know about each other:
# Prowlarr feeds indexer config to Sonarr/Radarr/Lidarr; the *arrs send
# grabs to qBittorrent under per-arr categories and hardlink completed
# downloads into their libraries; Bazarr writes subtitles next to
# Sonarr's + Radarr's videos; Jellyseerr forwards family requests to
# Sonarr/Radarr. shared.nix carries the cross-cutting `media` group +
# the @downloads/@library tmpfiles. Adding a new *arr (Readarr,
# Whisparr, etc.) lands here.
_: {
  imports = [
    ./shared.nix
    ./bazarr.nix
    ./jellyseerr.nix
    ./lidarr.nix
    ./prowlarr.nix
    ./qbittorrent.nix
    ./radarr.nix
    ./recyclarr.nix
    ./sonarr.nix
  ];
}
