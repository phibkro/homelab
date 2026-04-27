# *arr stack — coupled cluster.
#
# These services know about each other:
#   * Prowlarr aggregates indexers and pushes search config to Sonarr,
#     Radarr, Lidarr via per-app API key.
#   * Sonarr/Radarr/Lidarr send grabs to qBittorrent under per-arr
#     categories (tv-sonarr, movies-radarr, music-lidarr) and import
#     completed downloads from qBittorrent's save dir.
#   * Bazarr watches Sonarr's + Radarr's libraries to fetch subtitles
#     into the same media tree.
#   * Jellyseerr presents the family-facing request UI and forwards
#     approved requests into Sonarr/Radarr.
#   * shared.nix sets up the `media` group, /mnt/media/streaming
#     ownership, and the tmpfiles for /mnt/media/streaming/{shows,
#     movies,music,books,comics,.downloads}.
#
# All seven arrs + qBittorrent need to be deployed together for the
# pipeline to be coherent — that's why this folder exists. Adding a
# new *arr (Readarr, Whisparr, etc.) lands here.
_: {
  imports = [
    ./shared.nix
    ./bazarr.nix
    ./jellyseerr.nix
    ./lidarr.nix
    ./prowlarr.nix
    ./qbittorrent.nix
    ./radarr.nix
    ./sonarr.nix
  ];
}
