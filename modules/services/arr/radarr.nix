{
  config,
  lib,
  ...
}:

lib.mkMerge [
  {
    nori.services.radarr.tags = [ "media-server" ];

    nori.lanRoutes.movies = {
      port = 7878;
      runsOn = "workstation";
      monitor = { };
      audience = "operator";
      dashboard = {
        title = "Radarr";
        icon = "si:radarr";
        group = "Acquire";
        description = "Movie automation";
      };
    };
  }
  (lib.mkIf config.nori.services.radarr.enabled {
    /*
      Radarr — movie management. Same role as Sonarr but for films:
      watches Prowlarr for releases, hands grabs to qBittorrent, hardlinks
      finished movies into the movies library.

      First-run setup:
        1. Visit https://movies.nori.lan
        2. Set admin password
        3. Settings → Media Management → Root Folders →
             /mnt/media/downloads/movies
        3a. Settings → Media Management → "Importing" →
              "Minimum Free Space When Importing" → 5 GB.
              See sonarr.nix for the rationale + qbittorrent.nix for the
              wedge this prevents.
        4. Settings → Download Clients → Add → qBittorrent
             Host: localhost  Port: 8083
             Username/Password: from qBittorrent
             Category: movies-radarr
        5. Copy Radarr's API key from Settings → General → API Key.
           Add to Prowlarr → Settings → Apps → Radarr.
        6. Add Movies via the UI.
    */
    services.radarr = {
      enable = true;
      user = "radarr";
      group = "radarr";
      openFirewall = false;
    };

    # See sonarr.nix for the env-var override + auth-disabled rationale.
    systemd.services.radarr.environment = {
      RADARR__AUTH__METHOD = "Forms";
      RADARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
    };

    users.users.radarr.extraGroups = [ "media" ];

    nori.harden.radarr.binds = [ config.nori.fs.downloads.path ];

    nori.backups.radarr.include = [ "/var/lib/radarr" ];
  })
]
