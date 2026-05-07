{
  config,
  lib,
  ...
}:

let
  # Dashboard catalog is *not* maintained in this file — it's derived
  # from `config.nori.lanRoutes`. Each service module that should
  # appear declares a `dashboard = { ... }` block on its own lanRoute
  # (see modules/effects/lan-route.nix for the schema). Glance reads
  # the collected attrset and maps to its widget shapes.
  #
  # Adding a new service = zero glance.nix edits. Removing a service
  # or hiding it from the dashboard = remove or unset its dashboard
  # block on the route. URL drift is impossible: the URL is derived
  # from the route name as `https://<n>.nori.lan`.
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
{
  # Glance — fast, single-binary Go dashboard. Family-facing landing
  # page at home.nori.lan.
  #
  # Three-column layout (small | full | small) — on desktop they appear
  # side-by-side; on phone they stack as scrollable sections.
  #
  #   Status   (col 1, small)  observational state — calendar, weather,
  #                            host CPU/RAM/disk
  #   Apps     (col 2, full)   navigation — grouped bookmarks for all
  #                            *.nori.lan
  #   Read     (col 3, small)  consumption — Twitch live-state, RSS
  #
  # Cross-host stats (Pi) and service uptime monitoring intentionally
  # NOT inline — Beszel (Pi-hosted) is the canonical stats plane (it
  # survives station outages which a station-hosted widget cannot);
  # Gatus is the canonical uptime monitor. Both reachable from the
  # Admin bookmark group.
  #
  # The Apps column's bookmarks derive from
  # `config.nori.lanRoutes.<n>.dashboard` blocks across all service
  # modules. Adding / renaming a service is a one-place edit on
  # *that service's module*; this file doesn't change.
  #
  # Default port 8080 collides with Open WebUI; remapped to 8086.
  #
  # Icon prefixes (declared per-service): si:<slug> (Simple Icons) or
  # sh:<slug> (selfh.st icons). selfh.st has the homelab-specific
  # brands Simple Icons doesn't carry.
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
                # Built-in host stats (CPU / RAM / disk) for workstation
                # itself — no external deps, complements Beszel.
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
                # Daily reading stream below the live-state.
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

  nori.lanRoutes.home = {
    port = 8086;
    monitor = { };
    audience = "public";
    # No `dashboard` block — Glance shouldn't link to itself.
  };

  # Stateless — Glance's dashboard config lives in Nix (this module
  # plus each service's lanRoute.dashboard). No persistent state worth
  # preserving across rebuilds. DynamicUser.
  nori.backups.glance.skip = "Stateless — dashboard config rendered from Nix.";
}
