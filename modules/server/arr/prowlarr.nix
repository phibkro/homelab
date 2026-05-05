{
  config,
  lib,
  pkgs,
  ...
}:

{
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

  # See sonarr.nix header comment for the rationale.
  systemd.services.prowlarr.environment = {
    PROWLARR__AUTH__METHOD = "Forms";
    PROWLARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
  };

  # Note: the prowlarr module runs the service as the `prowlarr` user
  # but doesn't accept user/group options to add to extra groups
  # (see /run/current-system/sw/share/nixos/modules — module hardcodes
  # User=prowlarr). If we ever need the prowlarr user in `media` for
  # cross-service file access, override via systemd.services.prowlarr
  # .serviceConfig.SupplementaryGroups; for now, prowlarr only does
  # API calls to other services and doesn't touch /mnt/media.

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

  # Pattern A — indexer list + per-app links. DynamicUser symlink.
  nori.backups.prowlarr.paths = [ "/var/lib/private/prowlarr" ];
}
