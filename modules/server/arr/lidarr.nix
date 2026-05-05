{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Lidarr — music management. Same role as Sonarr/Radarr but for music:
  # watches Prowlarr for releases, hands grabs to qBittorrent, hardlinks
  # finished tracks into the music library. Library lives in @streaming
  # (re-derivable tier — auto-grabbed; if a track gets lost, Lidarr will
  # re-grab from indexers).
  #
  # Music *playback* is handled by Jellyfin's existing music section
  # (already running at media.nori.lan); Lidarr only manages
  # acquisition + organization. Navidrome was considered as an
  # alternative Subsonic-protocol playback server but deferred —
  # Jellyfin covers the case for now.
  #
  # First-run setup:
  #   1. Visit https://music.nori.lan
  #   2. Set admin password
  #   3. Settings → Media Management → Root Folders →
  #        /mnt/media/streaming/music
  #   4. Settings → Download Clients → Add → qBittorrent
  #        Host: localhost  Port: 8083
  #        Username/Password: from qBittorrent
  #        Category: music-lidarr
  #   5. Copy Lidarr's API key from Settings → General → API Key.
  #      In Prowlarr (indexers.nori.lan) → Settings → Apps → Add →
  #      Lidarr.
  #   6. Add Artists / Albums via the UI.
  services.lidarr = {
    enable = true;
    user = "lidarr";
    group = "lidarr";
    openFirewall = false;
  };

  users.users.lidarr.extraGroups = [ "media" ];

  nori.harden.lidarr.binds = [ "/mnt/media/streaming" ];

  nori.lanRoutes.music = {
    port = 8686;
    monitor = { };
  };

  # Pattern A — same shape as sonarr/radarr.
  nori.backups.lidarr.paths = [ "/var/lib/lidarr" ];
}
