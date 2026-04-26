{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Sonarr — TV show management. Watches Prowlarr for new episode
  # availability, hands matches to qBittorrent, scans the download
  # complete dir, hardlinks finished episodes into the shows library.
  #
  # First-run setup:
  #   1. Visit https://tv.nori.lan
  #   2. Set admin password
  #   3. Settings → Media Management → Root Folders →
  #        /mnt/media/streaming/shows
  #   4. Settings → Download Clients → Add → qBittorrent
  #        Host: localhost  Port: 8083
  #        Username/Password: from qBittorrent's WebUI auth
  #        Category: tv-sonarr  (Sonarr files downloads under this label)
  #   5. Copy Sonarr's API key from Settings → General → API Key.
  #      In Prowlarr (indexers.nori.lan) → Settings → Apps → Add →
  #      Sonarr. Paste API key. Once linked, indexer changes propagate.
  #   6. Add Series via the UI; Sonarr picks an indexer + sends to
  #      qBittorrent.
  services.sonarr = {
    enable = true;
    user = "sonarr";
    group = "sonarr";
    openFirewall = false;
  };

  # Hardlink target paths share `media` group with qBittorrent + Radarr +
  # Bazarr. Without group membership, post-download imports fail with
  # "permission denied".
  users.users.sonarr.extraGroups = [ "media" ];

  systemd.services.sonarr.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
    BindPaths = [ "/mnt/media/streaming" ];
  };

  nori.lanRoutes.tv = {
    port = 8989;
    monitor = { };
  };
}
