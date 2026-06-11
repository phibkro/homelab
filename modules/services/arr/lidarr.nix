{
  config,
  lib,
  ...
}:

lib.mkMerge [
  {
    nori.services.lidarr.tags = [ "media-server" ];

    nori.lanRoutes.music = {
      port = 8686;
      runsOn = "workstation";
      monitor = { };
      audience = "operator";
      dashboard = {
        title = "Lidarr";
        icon = "sh:lidarr";
        group = "Acquire";
        description = "Music automation";
      };
    };
  }
  (lib.mkIf config.nori.services.lidarr.enabled {
    # Lidarr — music management. Same role as Sonarr/Radarr but for music:
    # watches Prowlarr for releases, hands grabs to qBittorrent, hardlinks
    # finished tracks into the music library. Library lives under
    # @library (curated tier — irreplaceable), specifically
    # `${nori.fs.library.path}/music`. Sibling tiers under library:
    # books (calibre-web), comics (komga). Navidrome on aurora reads
    # the same path post-cutover; Jellyfin's music section continues
    # to serve as the workstation-resident playback option.
    #
    # First-run setup:
    #   1. Visit https://music.${nori.domain}
    #   2. Set admin password
    #   3. Settings → Media Management → Root Folders →
    #        /mnt/media/library/music
    #   3a. Settings → Media Management → "Importing" →
    #         "Minimum Free Space When Importing" → 5 GB.
    #         See sonarr.nix for the rationale + qbittorrent.nix for the
    #         wedge this prevents.
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

    # See sonarr.nix for the env-var override + auth-disabled rationale.
    systemd.services.lidarr.environment = {
      LIDARR__AUTH__METHOD = "Forms";
      LIDARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
    };

    users.users.lidarr.extraGroups = [ "media" ];

    nori.harden.lidarr.binds = [
      config.nori.fs.downloads.path
      "${config.nori.fs.library.path}/music"
    ];

    nori.backups.lidarr.include = [ "/var/lib/lidarr" ];
  })
]
