{
  config,
  lib,
  ...
}:

lib.mkMerge [
  { nori.services.prowlarr.tags = [ "media-server" ]; }
  (lib.mkIf config.nori.services.prowlarr.enabled {
    # Prowlarr — indexer aggregator for the *arr stack. Holds the list of
    # torrent trackers / Usenet indexers in one place; Sonarr + Radarr
    # query Prowlarr for searches instead of each maintaining its own
    # indexer list. One source of truth.
    #
    # First-run setup:
    #   1. Visit https://indexers.nori.lan
    #   2. Set admin password
    #   3. Settings → General → Authentication → "Forms (Login Page)"
    #      (default; tailnet trust is the boundary, but local-only access
    #      via Caddy already gates this)
    #   4. Indexers → Add Indexer → pick public trackers (1337x, RARBG
    #      successors, Nyaa for anime, etc.). Configure category mappings
    #      defaults are usually fine.
    #   5. Settings → Apps → Add Sonarr (URL http://localhost:8989, copy
    #      Sonarr's API key from its Settings → General). Repeat for Radarr.
    #      Once linked, indexer changes in Prowlarr propagate to all *arrs.
    services.prowlarr = {
      enable = true;
      openFirewall = false;
    };

    # See sonarr.nix for the env-var override + auth-disabled rationale.
    systemd.services.prowlarr.environment = {
      PROWLARR__AUTH__METHOD = "Forms";
      PROWLARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
    };

    # Upstream prowlarr module hardcodes User=prowlarr and exposes no
    # extraGroups knob. Prowlarr only makes API calls to other *arrs and
    # never touches /mnt/media, so it doesn't need `media`; if that ever
    # changes, override via serviceConfig.SupplementaryGroups.

    nori.harden.prowlarr = { };

    nori.lanRoutes.indexers = {
      port = 9696;
      monitor = { };
      audience = "operator";
      dashboard = {
        title = "Prowlarr";
        icon = "sh:prowlarr";
        group = "Acquire";
        description = "Indexer aggregator";
      };
    };

    # DynamicUser — /var/lib/prowlarr is a symlink; restic stores the link
    # not the target, so back up the real path.
    nori.backups.prowlarr.include = [ "/var/lib/private/prowlarr" ];
  })
]
