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

  # Servarr config.xml settings overridden via env vars (double-
  # underscore-prefixed keys take precedence over existing values
  # in config.xml at startup; see Servarr post-install-configuration
  # docs). Forces auth-disabled-for-localhost so Caddy's forward-auth
  # is the only gate for browser access; SSH-tunnel-direct still
  # requires the Forms login as a defense-in-depth fallback.
  systemd.services.sonarr.environment = {
    SONARR__AUTH__METHOD = "Forms";
    SONARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
  };

  # Hardlink target paths share `media` group with qBittorrent + Radarr +
  # Bazarr. Without group membership, post-download imports fail with
  # "permission denied".
  users.users.sonarr.extraGroups = [ "media" ];

  nori.harden.sonarr.binds = [ config.nori.fs.streaming.path ];

  nori.lanRoutes.tv = {
    port = 8989;
    monitor = { };
    audience = "operator";
    dashboard = {
      title = "Sonarr";
      icon = "si:sonarr";
      group = "Acquire";
      description = "TV show automation";
    };
  };

  # Pattern A — config + history sqlite + custom formats. Sonarr
  # writes infrequently; file-snapshot consistency is acceptable
  # alongside btrbk hourly snapshots as a safety net.
  nori.backups.sonarr.paths = [ "/var/lib/sonarr" ];
}
