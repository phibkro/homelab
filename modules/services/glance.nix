{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Glance — fast, single-binary Go dashboard. Family-facing landing
  # page at home.nori.lan that surfaces every other *.nori.lan service
  # in one place plus optional widgets (clock, RSS, weather, etc.).
  #
  # Default port 8080 collides with Open WebUI; remapped to 8086.
  #
  # Config is YAML via `services.glance.settings`; iterate by editing
  # this file + `just rebuild` (live config reload not currently wired).
  # Glance docs: https://github.com/glanceapp/glance
  services.glance = {
    enable = true;
    openFirewall = false;
    settings = {
      server = {
        host = "127.0.0.1";
        port = 8086;
      };
      pages = [
        {
          name = "Home";
          columns = [
            {
              size = "full";
              widgets = [
                # Clock + weather placeholder — add lat/lon later via
                # the weather widget.
                {
                  type = "calendar";
                  start-sunday = false;
                }
                # Service uptime — Glance polls each URL and shows
                # green/red. Mirrors the Gatus dashboard but is
                # family-readable rather than admin-grade.
                {
                  type = "monitor";
                  cache = "5m";
                  title = "Services";
                  sites = [
                    {
                      title = "Jellyfin";
                      url = "https://media.nori.lan";
                    }
                    {
                      title = "Open WebUI";
                      url = "https://chat.nori.lan";
                    }
                    {
                      title = "Sonarr";
                      url = "https://tv.nori.lan";
                    }
                    {
                      title = "Radarr";
                      url = "https://movies.nori.lan";
                    }
                    {
                      title = "Lidarr";
                      url = "https://music.nori.lan";
                    }
                    {
                      title = "Prowlarr";
                      url = "https://indexers.nori.lan";
                    }
                    {
                      title = "Bazarr";
                      url = "https://subtitles.nori.lan";
                    }
                    {
                      title = "Jellyseerr";
                      url = "https://requests.nori.lan";
                    }
                    {
                      title = "qBittorrent";
                      url = "https://downloads.nori.lan";
                    }
                    {
                      title = "calibre-web";
                      url = "https://books.nori.lan";
                    }
                    {
                      title = "Komga";
                      url = "https://comics.nori.lan";
                    }
                    {
                      title = "Beszel";
                      url = "https://metrics.nori.lan";
                    }
                    {
                      title = "Gatus";
                      url = "https://status.nori.lan";
                    }
                    {
                      title = "Authelia";
                      url = "https://auth.nori.lan";
                    }
                  ];
                }
              ];
            }
          ];
        }
      ];
    };
  };

  systemd.services.glance.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
  };

  nori.lanRoutes.home = {
    port = 8086;
    monitor = { };
  };
}
