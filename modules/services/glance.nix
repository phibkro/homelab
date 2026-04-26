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
  # Icon prefixes used:
  #   si:<slug>  Simple Icons — popular brands; covers Sonarr, Radarr,
  #              qBittorrent, Syncthing, Jellyfin, Immich.
  #   sh:<slug>  selfh.st icons — curated for self-hosted services;
  #              covers the rest (Bazarr, Gatus, Komga, Lidarr,
  #              Jellyseerr, Open WebUI, Prowlarr, Beszel,
  #              calibre-web, Radicale, Authelia).
  # If an icon doesn't render, try the other prefix or omit the
  # `icon =` line entirely (Glance falls back to the title's first
  # letter in a colored box).
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
                # Built-in host stats (CPU / RAM / disk) for nori-station
                # itself — no external deps, complements Beszel.
                {
                  type = "server-stats";
                  servers = [
                    {
                      type = "local";
                      name = "nori-station";
                    }
                  ];
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
                # Uptime monitor — green/red status dots for every
                # *.nori.lan. Polled every 5 min. allow-insecure on
                # syncthing because Caddy's internal CA isn't always
                # accepted by Glance's HTTP client even with system
                # trust populated.
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
                      icon = "sh:open-webui";
                    }
                    {
                      title = "Calibre-web (books)";
                      url = "https://books.nori.lan";
                      icon = "sh:calibre-web";
                    }
                    {
                      title = "Komga (comics)";
                      url = "https://comics.nori.lan";
                      icon = "sh:komga";
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
                      icon = "sh:lidarr";
                    }
                    {
                      title = "Prowlarr (indexers)";
                      url = "https://indexers.nori.lan";
                      icon = "sh:prowlarr";
                    }
                    {
                      title = "Bazarr (subtitles)";
                      url = "https://subtitles.nori.lan";
                      icon = "sh:bazarr";
                    }
                    {
                      title = "Jellyseerr (requests)";
                      url = "https://requests.nori.lan";
                      icon = "sh:jellyseerr";
                    }
                    {
                      title = "qBittorrent (downloads)";
                      url = "https://downloads.nori.lan";
                      icon = "si:qbittorrent";
                    }
                    {
                      title = "Radicale (calendar)";
                      url = "https://calendar.nori.lan";
                      icon = "sh:radicale";
                    }
                    {
                      title = "Syncthing (sync)";
                      url = "https://sync.nori.lan";
                      icon = "si:syncthing";
                      allow-insecure = true;
                    }
                    {
                      title = "Beszel (metrics)";
                      url = "https://metrics.nori.lan";
                      icon = "sh:beszel";
                    }
                    {
                      title = "Gatus (status)";
                      url = "https://status.nori.lan";
                      icon = "sh:gatus";
                    }
                    {
                      title = "Authelia (auth)";
                      url = "https://auth.nori.lan";
                      icon = "sh:authelia";
                    }
                  ];
                }
                # Bookmarks — descriptions + grouping that the monitor
                # can't carry. Same URLs grouped by purpose. Doesn't
                # poll (use the monitor above for "is it up?").
                {
                  type = "bookmarks";
                  groups = [
                    {
                      title = "Consume";
                      links = [
                        {
                          title = "Jellyfin";
                          url = "https://media.nori.lan";
                          description = "Movies, shows, music — server-rendered";
                          icon = "si:jellyfin";
                        }
                        {
                          title = "Immich";
                          url = "https://photos.nori.lan";
                          description = "Photo library + face recognition";
                          icon = "si:immich";
                        }
                        {
                          title = "calibre-web";
                          url = "https://books.nori.lan";
                          description = "Ebook reader + OPDS";
                          icon = "sh:calibre-web";
                        }
                        {
                          title = "Komga";
                          url = "https://comics.nori.lan";
                          description = "Comics + manga + OPDS";
                          icon = "sh:komga";
                        }
                        {
                          title = "Open WebUI";
                          url = "https://chat.nori.lan";
                          description = "Local LLM chat (Ollama-backed)";
                          icon = "sh:open-webui";
                        }
                      ];
                    }
                    {
                      title = "Acquire";
                      links = [
                        {
                          title = "Jellyseerr";
                          url = "https://requests.nori.lan";
                          description = "Request shows / movies (family-facing)";
                          icon = "sh:jellyseerr";
                        }
                        {
                          title = "Sonarr";
                          url = "https://tv.nori.lan";
                          description = "TV show automation";
                          icon = "si:sonarr";
                        }
                        {
                          title = "Radarr";
                          url = "https://movies.nori.lan";
                          description = "Movie automation";
                          icon = "si:radarr";
                        }
                        {
                          title = "Lidarr";
                          url = "https://music.nori.lan";
                          description = "Music automation";
                          icon = "sh:lidarr";
                        }
                        {
                          title = "Bazarr";
                          url = "https://subtitles.nori.lan";
                          description = "Subtitle automation";
                          icon = "sh:bazarr";
                        }
                        {
                          title = "Prowlarr";
                          url = "https://indexers.nori.lan";
                          description = "Indexer aggregator";
                          icon = "sh:prowlarr";
                        }
                        {
                          title = "qBittorrent";
                          url = "https://downloads.nori.lan";
                          description = "Download client";
                          icon = "si:qbittorrent";
                        }
                      ];
                    }
                    {
                      title = "Personal";
                      links = [
                        {
                          title = "Radicale";
                          url = "https://calendar.nori.lan";
                          description = "CalDAV / CardDAV — phone calendar + contacts";
                          icon = "sh:radicale";
                        }
                        {
                          title = "Syncthing";
                          url = "https://sync.nori.lan";
                          description = "Cross-device file sync";
                          icon = "si:syncthing";
                        }
                      ];
                    }
                    {
                      title = "Admin";
                      links = [
                        {
                          title = "Beszel";
                          url = "https://metrics.nori.lan";
                          description = "System metrics (CPU / RAM / disk / GPU)";
                          icon = "sh:beszel";
                        }
                        {
                          title = "Gatus";
                          url = "https://status.nori.lan";
                          description = "Service uptime + alerts";
                          icon = "sh:gatus";
                        }
                        {
                          title = "Authelia";
                          url = "https://auth.nori.lan";
                          description = "OIDC SSO issuer";
                          icon = "sh:authelia";
                        }
                      ];
                    }
                  ];
                }
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
