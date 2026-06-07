# *arr stack — coupled cluster. These services know about each other:
#
#   * Prowlarr aggregates indexers, pushes search config to Sonarr,
#     Radarr, Lidarr via per-app API key.
#   * Sonarr / Radarr / Lidarr send grabs to qBittorrent under per-arr
#     categories (tv-sonarr, movies-radarr, music-lidarr) and import
#     completed downloads via hardlink (same-subvol).
#   * Bazarr watches Sonarr's + Radarr's libraries to fetch subtitles
#     into the same media tree.
#   * Jellyseerr presents the family-facing request UI and forwards
#     approved requests into Sonarr / Radarr.
#   * shared.nix carries the cross-cutting `media` group + the
#     @downloads / @library tmpfiles.
#
# All seven *arrs + qBittorrent need to be deployed together for the
# pipeline to be coherent. Adding a new *arr (Readarr, Whisparr, …)
# lands here.
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
