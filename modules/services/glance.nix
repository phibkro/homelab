{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Glance — fast, single-binary Go dashboard. Family-facing landing
  # page at home.nori.lan that surfaces every other *.nori.lan service
  # in one place plus a daily-check stream (calendar, weather, news,
  # release feeds for tools we actually use).
  #
  # Default port 8080 collides with Open WebUI; remapped to 8086.
  #
  # Config is YAML via `services.glance.settings`; iterate by editing
  # this file + just rebuild. Layout follows the canonical
  # docs/glance.yml template (small | full | small) adapted with our
  # actual services + interests.
  #
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
          # Single-page dashboard; hide the (unused) navigation.
          hide-desktop-navigation = true;
          columns = [
            # ---------------- Left (small) — at-a-glance ----------------
            {
              size = "small";
              widgets = [
                {
                  type = "calendar";
                  first-day-of-week = "monday";
                }
                {
                  type = "weather";
                  location = "Oslo, Norway";
                  units = "metric";
                  hour-format = "24h";
                }
                {
                  type = "rss";
                  title = "Self-hosted news";
                  limit = 8;
                  collapse-after = 3;
                  cache = "12h";
                  feeds = [
                    {
                      url = "https://selfh.st/rss/";
                      title = "selfh.st";
                    }
                    {
                      url = "https://discourse.nixos.org/latest.rss";
                      title = "NixOS Discourse";
                      limit = 3;
                    }
                  ];
                }
              ];
            }

            # ---------------- Center (full) — the lab ----------------
            {
              size = "full";
              widgets = [
                # The biggest widget on the page — uptime + click-through
                # for every *.nori.lan service. Polled every 5 min.
                {
                  type = "monitor";
                  cache = "5m";
                  title = "Services";
                  sites = [
                    {
                      title = "Jellyfin (media)";
                      url = "https://media.nori.lan";
                      icon = "si:jellyfin";
                    }
                    {
                      title = "Immich (photos)";
                      url = "https://photos.nori.lan";
                      icon = "si:immich";
                    }
                    {
                      title = "Open WebUI (chat)";
                      url = "https://chat.nori.lan";
                      icon = "si:openwebui";
                    }
                    {
                      title = "Calibre-web (books)";
                      url = "https://books.nori.lan";
                      icon = "si:calibreweb";
                    }
                    {
                      title = "Komga (comics)";
                      url = "https://comics.nori.lan";
                      icon = "si:komga";
                    }
                    {
                      title = "Sonarr (tv)";
                      url = "https://tv.nori.lan";
                      icon = "si:sonarr";
                    }
                    {
                      title = "Radarr (movies)";
                      url = "https://movies.nori.lan";
                      icon = "si:radarr";
                    }
                    {
                      title = "Lidarr (music)";
                      url = "https://music.nori.lan";
                      icon = "si:lidarr";
                    }
                    {
                      title = "Prowlarr (indexers)";
                      url = "https://indexers.nori.lan";
                      icon = "si:prowlarr";
                    }
                    {
                      title = "Bazarr (subtitles)";
                      url = "https://subtitles.nori.lan";
                      icon = "si:bazarr";
                    }
                    {
                      title = "Jellyseerr (requests)";
                      url = "https://requests.nori.lan";
                      icon = "si:jellyseerr";
                    }
                    {
                      title = "qBittorrent (downloads)";
                      url = "https://downloads.nori.lan";
                      icon = "si:qbittorrent";
                    }
                    {
                      title = "Radicale (calendar)";
                      url = "https://calendar.nori.lan";
                    }
                    {
                      title = "Syncthing (sync)";
                      url = "https://sync.nori.lan";
                      icon = "si:syncthing";
                    }
                    {
                      title = "Beszel (metrics)";
                      url = "https://metrics.nori.lan";
                    }
                    {
                      title = "Gatus (status)";
                      url = "https://status.nori.lan";
                      icon = "si:gatus";
                    }
                    {
                      title = "Authelia (auth)";
                      url = "https://auth.nori.lan";
                      icon = "si:authelia";
                    }
                  ];
                }
                # Daily reading stream — Hacker News + Lobsters side by
                # side, with the same widget grouping as the canonical
                # Glance template.
                {
                  type = "group";
                  widgets = [
                    { type = "hacker-news"; }
                    { type = "lobsters"; }
                  ];
                }
                {
                  type = "reddit";
                  subreddit = "selfhosted";
                  show-thumbnails = true;
                }
              ];
            }

            # ---------------- Right (small) — releases + clock ----------------
            {
              size = "small";
              widgets = [
                {
                  type = "releases";
                  title = "Releases";
                  cache = "1d";
                  # Without auth, GitHub API rate-limits to 60 req/h.
                  # Currently 8 repos × 1 req each, polled daily — fine
                  # under the limit. Add a token via sops if it grows.
                  repositories = [
                    "hyprwm/Hyprland"
                    "NixOS/nixpkgs"
                    "nix-community/home-manager"
                    "Mic92/sops-nix"
                    "glanceapp/glance"
                    "immich-app/immich"
                    "syncthing/syncthing"
                    "restic/restic"
                  ];
                }
                {
                  type = "rss";
                  title = "Releases & blog";
                  limit = 6;
                  collapse-after = 3;
                  cache = "12h";
                  feeds = [
                    {
                      url = "https://nixos.org/blog/announcements-feed.xml";
                      title = "NixOS announcements";
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
