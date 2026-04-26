{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Glance — fast, single-binary Go dashboard. Family-facing landing
  # page at home.nori.lan.
  #
  # Three-column layout (small | full | small) — on desktop they appear
  # side-by-side; on phone they stack as scrollable sections (the
  # ":pages: hint" Glance shows on narrow viewports).
  #
  #   Status   (col 1, small)  observational state — calendar, weather,
  #                            host CPU/RAM/disk
  #   Apps     (col 2, full)   navigation — uptime monitor + grouped
  #                            bookmarks for all *.nori.lan
  #   Read     (col 3, small)  consumption — HN/Lobsters/Reddit, RSS,
  #                            release feeds
  #
  # Default port 8080 collides with Open WebUI; remapped to 8086.
  #
  # Icon prefixes: si:<slug> (Simple Icons) or sh:<slug> (selfh.st
  # icons). selfh.st has the homelab-specific brands Simple Icons
  # doesn't carry.
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
            # ============== Col 1 — Status ==============
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
              ];
            }

            # ============== Col 2 — Apps / Services ==============
            {
              size = "full";
              widgets = [
                # Uptime monitor — green/red status dots for every
                # *.nori.lan service. allow-insecure on syncthing
                # because Caddy's internal CA isn't always accepted by
                # Glance's HTTP client.
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
                # Bookmarks — grouped + descriptive view, complements
                # the monitor (which answers "is it up?" but doesn't
                # describe each).
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
              ];
            }

            # ============== Col 3 — Read ==============
            {
              size = "small";
              widgets = [
                # Daily reading stream first — most-likely-to-glance.
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
                {
                  type = "releases";
                  title = "Releases";
                  cache = "1d";
                  # Without auth, GitHub API rate-limits to 60 req/h.
                  # 8 repos × 1 req daily — well under. Add a sops
                  # token if more get added.
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
                  title = "NixOS announcements";
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
