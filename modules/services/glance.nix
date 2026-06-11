{
  config,
  lib,
  ...
}:

let
  # Dashboard catalog is *not* maintained here — it's derived from
  # `config.nori.lanRoutes`. Each service module declares a
  # `dashboard = { ... }` block on its own lanRoute (schema in
  # modules/effects/lan-route.nix); URL is derived from the route name
  # as `https://<n>.nori.lan`, so URL drift is impossible.
  dashed = lib.filterAttrs (_: r: r.dashboard != null) config.nori.lanRoutes;

  # Glance renders bookmark groups in the order given. Sort by the
  # group's position in this list, falling back to alphabetical
  # within a group via attrset key order. Consume first (most-clicked),
  # Admin last.
  groupOrder = [
    "Consume"
    "Acquire"
    "Personal"
    "Projects"
    "Admin"
  ];

  toBookmarkLink = name: r: {
    inherit (r.dashboard) title icon description;
    url = "https://${name}.nori.lan";
  };

  inGroup = g: lib.filterAttrs (_: r: r.dashboard.group == g) dashed;
in
lib.mkMerge [
  {
    nori.services.glance.tags = [
      "family-tier"
      "stateless"
    ];

    nori.lanRoutes.home = {
      port = 8086;
      runsOn = "aurora";
      monitor = { };
      audience = "public";
      # No `dashboard` block — Glance shouldn't link to itself.
    };
  }
  (lib.mkIf config.nori.services.glance.enabled {
    # Glance — family-facing landing page at home.nori.lan.
    #
    # Three-column layout (small | full | small) — desktop side-by-side,
    # phone stacks as scrollable sections.
    #
    #   Status   (col 1, small)  observational — calendar, weather, host stats
    #   Apps     (col 2, full)   navigation — grouped bookmarks for *.nori.lan
    #   Read     (col 3, small)  consumption — Twitch live-state, RSS
    #
    # Cross-host stats (Pi) and service uptime monitoring intentionally
    # NOT inline — Beszel (Pi-hosted) is the canonical stats plane (it
    # survives station outages which a station-hosted widget cannot);
    # Gatus is the canonical uptime monitor. Both reachable from the
    # Admin bookmark group.
    #
    # Default port 8080 collides with Open WebUI; remapped to 8086.
    #
    # Icon prefixes (declared per-service): si:<slug> (Simple Icons) or
    # sh:<slug> (selfh.st icons — has homelab brands Simple Icons doesn't).
    #
    # Glance docs: https://github.com/glanceapp/glance
    services.glance = {
      enable = true;
      openFirewall = false;
      settings = {
        server = {
          host = "0.0.0.0";
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
                  # Workstation host stats — complements Pi-hosted Beszel.
                  {
                    type = "server-stats";
                    servers = [
                      {
                        type = "local";
                        name = "workstation";
                      }
                    ];
                  }
                ];
              }

              # ============== Col 2 — Apps / Services ==============
              # Bookmarks-only — service uptime status was previously
              # rendered here as a `monitor` widget but is duplicated by
              # the dedicated Gatus instance (linked from the Admin
              # bookmark group). Removing the inline widget de-clutters
              # the family-facing landing page.
              {
                size = "full";
                widgets = [
                  {
                    type = "bookmarks";
                    groups = map (g: {
                      title = g;
                      links = lib.mapAttrsToList toBookmarkLink (inGroup g);
                    }) groupOrder;
                  }
                ];
              }

              # ============== Col 3 — Read ==============
              {
                size = "small";
                widgets = [
                  # Twitch live-state — surfaces a thumbnail + viewer
                  # count when channels are streaming, "offline" line
                  # otherwise. Time-sensitive (state changes per stream
                  # session), so this lives ABOVE the RSS feeds where
                  # the eye lands first.
                  {
                    type = "twitch-channels";
                    channels = [
                      "clintstevens"
                      "jerma985"
                    ];
                  }
                  {
                    type = "group";
                    widgets = [
                      {
                        type = "rss";
                        title = "Papers";
                        limit = 10;
                        cache = "12h";
                        feeds = [
                          {
                            url = "https://api.episciences.org/api/feed/rss/compositionality";
                            title = "Compositionality Journal";
                          }
                        ];
                      }
                      {
                        type = "rss";
                        title = "Dev";
                        limit = 10;
                        cache = "12h";
                        feeds = [
                          {
                            url = "https://ziglang.org/news/index.xml";
                            title = "Zig Lang";
                          }
                          {
                            url = "https://effect.website/blog/rss.xml";
                            title = "Effect TS";
                          }
                        ];
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

    nori.harden.glance = { };

    nori.backups.glance.skip = "Stateless — dashboard config rendered from Nix (this module + each service's lanRoute.dashboard).";
  })
]
