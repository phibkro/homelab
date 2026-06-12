{
  config,
  lib,
  ...
}:

lib.mkMerge [
  {
    nori.services.sonarr.tags = [ "media-server" ];

    nori.lanRoutes.tv = {
      port = 8989;
      runsOn = "workstation";
      exposeOnTailnet = true; # pi's Caddy proxies cross-host over tailnet
      monitor = { };
      audience = "operator";
      dashboard = {
        title = "Sonarr";
        icon = "si:sonarr";
        group = "Acquire";
        description = "TV show automation";
      };
    };
  }
  (lib.mkIf config.nori.services.sonarr.enabled {
    # Sonarr — TV show management. Watches Prowlarr for new episode
    # availability, hands matches to qBittorrent, scans the download
    # complete dir, hardlinks finished episodes into the shows library.
    #
    # First-run setup:
    #   1. Visit https://tv.nori.lan
    #   2. Set admin password
    #   3. Settings → Media Management → Root Folders →
    #        /mnt/media/downloads/shows
    #   3a. Settings → Media Management → "Importing" →
    #         "Minimum Free Space When Importing" → 5 GB.
    #         Prevents the wedge documented in qbittorrent.nix (the
    #         *arr stack queueing grabs past available headroom on
    #         @downloads). Lives in Sonarr's SQLite DB not config.xml,
    #         so env-var override doesn't reach it — UI only.
    #         See docs/runbooks/storage-full.md.
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

    # Servarr `<APP>__<SECTION>__<KEY>` env vars override config.xml at
    # startup. Auth disabled for localhost so Caddy's forward-auth is the
    # only browser gate; the Forms login still covers SSH-tunnel-direct
    # access as defense-in-depth.
    systemd.services.sonarr.environment = {
      SONARR__AUTH__METHOD = "Forms";
      SONARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
    };

    users.users.sonarr.extraGroups = [ "media" ];

    nori.harden.sonarr.binds = [ config.nori.fs.downloads.path ];

    # Pattern A — file-snapshot consistency is fine, sonarr writes
    # infrequently and btrbk hourly snapshots are the safety net.
    nori.backups.sonarr.include = [ "/var/lib/sonarr" ];
  })
]
