{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
    mkIf
    mapAttrs'
    nameValuePair
    filterAttrs
    ;
in
{
  # nori.lanRoutes — single source of truth for services exposed
  # under *.nori.lan. Each entry generates ALL of:
  #   * Caddy vhost: reverse proxy from <name>.nori.lan to the
  #     declared backend port
  #   * Blocky customDNS mapping: <name>.nori.lan → tailnet IP
  #   * Gatus monitor (if `monitor` is non-null)
  #   * Tailnet firewall opening (if `exposeOnTailnet`)
  #   * sops secret + env-file template (if `oidc` is non-null) — the
  #     consuming Authelia client list assembly lives in
  #     modules/server/authelia.nix, which reads back from
  #     config.nori.lanRoutes here.
  #
  # Service modules just declare their own routing inline:
  #
  #   nori.lanRoutes.chat = {
  #     port = 8080;
  #     oidc = {
  #       clientName  = "Open WebUI";
  #       redirectPath = "/oauth/oidc/callback";
  #     };
  #   };
  #
  # Hash material lives only in sops; see authelia.nix for how the
  # template config-filter injects it at runtime.
  #
  # No more Caddy + Blocky + Authelia + sops template edits per
  # service. Adding a new service later: one block in the module
  # that owns the service.
  #
  # ── OIDC env-file naming convention ─────────────────────────────
  # When `oidc` is non-null, lan-route generates a sops template
  # rendered to /run/secrets/rendered/oidc-<name>-env containing
  # `<secretEnvName>=<raw secret>`. Consuming service modules wire
  # this as an EnvironmentFile on their systemd unit:
  #
  #   systemd.services.<svc>.serviceConfig = {
  #     EnvironmentFile = config.sops.templates."oidc-<name>-env".path;
  #     SupplementaryGroups = [ "keys" ];
  #   };
  #
  # Plus the non-secret OIDC env vars (provider URL, client_id, etc.)
  # in `services.<svc>.environment` directly, since those vary per
  # service and aren't worth abstracting.

  options.nori.lanIp = mkOption {
    type = types.str;
    default =
      let
        candidates = lib.filterAttrs (_: h: h.role == "workhorse" && h.lanIp != null) config.nori.hosts;
        names = lib.attrNames candidates;
      in
      if lib.length names == 1 then
        (lib.head (lib.attrValues candidates)).lanIp
      else
        throw ''
          nori.lanIp: cannot pick a default — expected exactly one workhorse
          host with a non-null lanIp in the registry, found ${toString (lib.length names)}
          (${lib.concatStringsSep ", " names}). Set nori.lanIp explicitly,
          or update the host registry (flake.nix identityFor).
        '';
    defaultText = lib.literalExpression ''
      # the unique workhorse-with-lanIp from config.nori.hosts;
      # eval-fails if zero or more than one matches.
    '';
    description = ''
      LAN IP that *.nori.lan names resolve to. Derived from the
      nori.hosts registry as "the unique host with role=workhorse
      and a non-null lanIp" (see modules/effects/hosts.nix). When
      a future second workhorse with a static LAN lease lands, the
      derivation fails eval — surfaces the ambiguity instead of
      silently picking nori-station.

      Previously the workhorse's tailnet IP, which silently required
      every client to be on tailnet to reach any service — a sharp
      edge for LAN-resident devices that can't or don't run tailscale
      (chromecasts, printers, occasional guest devices). Using the
      LAN IP lets those clients hit services directly. Tailnet
      clients off-LAN still reach the same address via Pi's subnet
      route advertisement (services.tailscale.useRoutingFeatures =
      "server" in hosts/nori-pi/default.nix); the client side needs
      --accept-routes set in its tailscaled config.

      Consumers: Blocky's forwarder mode (modules/server/blocky.nix)
      and the Blocky DNS generator below. Both want a single "where
      does *.nori.lan live" address.
    '';
  };

  options.nori.lanRoutes = mkOption {
    default = { };
    description = ''
      Services to expose under *.nori.lan via Caddy reverse proxy +
      Blocky DNS. Attribute name = subdomain; value declares the
      backend.
    '';
    example = lib.literalExpression ''
      {
        jellyfin = { port = 8096; };
        chat = { port = 8080; };
        ai = { port = 11434; };
      }
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          port = mkOption {
            type = types.port;
            description = "Backend TCP port (validated 0-65535 at eval time).";
          };
          host = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = "Backend host for Caddy to proxy to.";
          };
          scheme = mkOption {
            type = types.enum [
              "http"
              "https"
            ];
            default = "http";
            description = "Backend scheme. Most services run plain HTTP; Caddy terminates TLS.";
          };
          exposeOnTailnet = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Open the backend port on the tailnet, bypassing Caddy.
              Default closed — Caddy on 443 is the canonical entry
              point. Opt in only when something needs direct port
              access (legacy clients, programmatic tools that don't
              handle Caddy's internal CA).
            '';
          };
          monitor = mkOption {
            default = null;
            description = ''
              If set, auto-generate a Gatus endpoint probing the route's
              backend directly (bypasses Caddy, tests just the service).
              Set to `{ }` to use defaults; override `path` for non-/
              health endpoints (e.g. ollama needs /api/tags).
            '';
            type = types.nullOr (
              types.submodule {
                options = {
                  path = mkOption {
                    type = types.str;
                    default = "/";
                    description = "Path appended to the backend URL for the probe.";
                  };
                  interval = mkOption {
                    type = types.str;
                    default = "60s";
                  };
                  failureThreshold = mkOption {
                    type = types.int;
                    default = 3;
                  };
                  conditions = mkOption {
                    type = types.listOf types.str;
                    default = [ "[STATUS] == 200" ];
                  };
                };
              }
            );
          };
          dashboard = mkOption {
            default = null;
            description = ''
              If set, this route appears on the Glance dashboard
              (https://home.nori.lan) — both as an uptime-monitor dot
              and as a grouped bookmark. The URL is derived from the
              route name as `https://<name>.nori.lan`; only metadata
              lives here. Glance consumes the whole nori.lanRoutes
              attrset and renders entries with `dashboard != null`.

              Routes that should NOT appear on the dashboard (e.g.
              cross-host backend lanRoutes whose canonical entry-point
              lives elsewhere, or services intentionally hidden from
              the family-facing landing page) leave `dashboard = null`.
            '';
            type = types.nullOr (
              types.submodule {
                options = {
                  title = mkOption {
                    type = types.str;
                    description = ''
                      Brand / display name shown on the dashboard
                      (e.g. "Jellyfin"). The route name is appended
                      as a parenthetical for the monitor widget —
                      "Jellyfin (media)".
                    '';
                  };
                  icon = mkOption {
                    type = types.str;
                    description = ''
                      Glance icon spec. Two prefixes:
                        si:<slug>  Simple Icons (most brand logos)
                        sh:<slug>  selfh.st icons (homelab brands
                                   that Simple Icons doesn't carry —
                                   Calibre-web, Komga, Beszel, …)
                    '';
                  };
                  group = mkOption {
                    type = types.enum [
                      "Consume"
                      "Acquire"
                      "Personal"
                      "Admin"
                    ];
                    description = ''
                      Bookmark group. Order on the dashboard follows
                      the enum order, not declaration order — Consume
                      first (most-clicked), Admin last.
                    '';
                  };
                  description = mkOption {
                    type = types.str;
                    description = ''
                      One-line blurb shown beneath the bookmark.
                      Function-oriented ("Movies, shows, music —
                      server-rendered"), not feature-list.
                    '';
                  };
                  allowInsecure = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Pass through to Glance's monitor `allow-insecure`
                      flag. Needed for routes whose backend cert isn't
                      trusted by Glance's HTTP client (e.g. Syncthing's
                      WebUI redirect through Caddy's internal CA).
                    '';
                  };
                };
              }
            );
          };
          oidc = mkOption {
            default = null;
            description = ''
              If set, this route gets:
                * an Authelia OIDC client entry (assembled by
                  modules/server/authelia.nix from this declaration)
                * a sops secret named `oidc-<name>-client-secret`
                * a sops env-file template named `oidc-<name>-env`
                  containing `<secretEnvName>=<raw>`, ready to wire as
                  systemd EnvironmentFile in the consuming module.

              Set to `null` (default) for routes that don't use SSO.
            '';
            type = types.nullOr (
              types.submodule {
                options = {
                  clientName = mkOption {
                    type = types.str;
                    description = "Display name shown on Authelia consent screen.";
                  };
                  redirectPath = mkOption {
                    type = types.str;
                    description = ''
                      Path appended to https://<name>.nori.lan to form
                      the OIDC redirect URI. Service-specific:
                        Open WebUI:  /oauth/oidc/callback
                        PocketBase:  /api/oauth2-redirect
                        Vaultwarden: /identity/connect/oidc-signin
                    '';
                  };
                  scopes = mkOption {
                    type = types.listOf types.str;
                    default = [
                      "openid"
                      "profile"
                      "email"
                      "groups"
                    ];
                    description = ''
                      OIDC scopes the client may request. Add
                      `offline_access` for services that need refresh
                      tokens (e.g. Vaultwarden).
                    '';
                  };
                  authorizationPolicy = mkOption {
                    type = types.str;
                    default = "one_factor";
                    description = "Authelia access-control policy: `one_factor`, `two_factor`, or a custom-named policy.";
                  };
                  secretEnvName = mkOption {
                    type = types.str;
                    default = "OAUTH_CLIENT_SECRET";
                    description = ''
                      Env-var name written to the generated env file.
                      Defaults to OAUTH_CLIENT_SECRET (Open WebUI's
                      convention). Override per service:
                        Vaultwarden: SSO_CLIENT_SECRET
                        Some others: OPENID_CLIENT_SECRET / OIDC_CLIENT_SECRET
                    '';
                  };
                };
              }
            );
          };
        };
      }
    );
  };

  config = mkIf (config.nori.lanRoutes != { }) (
    let
      routes = config.nori.lanRoutes;
      ports = lib.mapAttrsToList (_: r: r.port) routes;
      names = lib.attrNames routes;
      oidcRoutes = filterAttrs (_: r: r.oidc != null) routes;
    in
    {
      # Hard constraints — eval fails if any of these are violated.
      # Cheaper than the corresponding documentation; the constraint
      # itself is the documentation.
      assertions = [
        {
          assertion = lib.length ports == lib.length (lib.unique ports);
          message = ''
            nori.lanRoutes have duplicate backend ports. Each route's
            `port` must be unique — Caddy can't reverse-proxy two
            services to the same backend port. Routes:
              ${lib.concatMapStringsSep ", " (n: "${n}=${toString routes.${n}.port}") names}
          '';
        }
        {
          assertion = lib.all (n: builtins.match "[a-z][a-z0-9-]*" n != null) names;
          message = ''
            nori.lanRoutes names must be DNS-safe: lowercase, must
            start with a letter, only [a-z0-9-] thereafter. Got: ${lib.concatStringsSep ", " names}
          '';
        }
        {
          assertion = lib.all (r: lib.hasPrefix "/" r.oidc.redirectPath) (lib.attrValues oidcRoutes);
          message = ''
            Every nori.lanRoutes.<n>.oidc.redirectPath must start
            with "/" — it's appended to https://<n>.nori.lan to form
            the OIDC redirect URI.
          '';
        }
      ];

      services.caddy.virtualHosts = mapAttrs' (
        name: cfg:
        nameValuePair "${name}.nori.lan" {
          extraConfig = "reverse_proxy ${cfg.scheme}://${cfg.host}:${toString cfg.port}";
        }
      ) config.nori.lanRoutes;

      services.blocky.settings.customDNS.mapping = mapAttrs' (
        name: _: nameValuePair "${name}.nori.lan" config.nori.lanIp
      ) config.nori.lanRoutes;

      # Tailnet firewall: open backend ports for opt-in routes only.
      # Default-deny aligns with the rest of the network policy
      # (Caddy on :80 + :443 from caddy.nix is the canonical entry).
      networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.flatten (
        lib.mapAttrsToList (_: cfg: lib.optional cfg.exposeOnTailnet cfg.port) config.nori.lanRoutes
      );

      # Auto-generated Gatus endpoints for routes that opt in via
      # `monitor`. Manual entries in modules/server/gatus.nix
      # (blocky-dns, samba-smb) coexist via list concatenation.
      services.gatus.settings.endpoints = lib.mkAfter (
        lib.mapAttrsToList (name: cfg: {
          inherit name;
          url = "${cfg.scheme}://${cfg.host}:${toString cfg.port}${cfg.monitor.path}";
          inherit (cfg.monitor) interval conditions;
          alerts = [
            {
              type = "ntfy";
              failure-threshold = cfg.monitor.failureThreshold;
              send-on-resolved = true;
            }
          ];
        }) (filterAttrs (_: cfg: cfg.monitor != null) config.nori.lanRoutes)
      );

      # OIDC plumbing for routes with `oidc` set. The Authelia client
      # entry is assembled by modules/server/authelia.nix reading
      # config.nori.lanRoutes — keeps single ownership of the clients
      # list (NixOS module merging on freeform-typed lists conflicts
      # rather than concatenates, so a centralized assembly site is
      # cleaner than mkMerge from multiple modules).
      #
      # Two sops secrets per OIDC route:
      #   * oidc-<name>-client-secret       — RAW secret, mode 0440
      #     group=keys, consumed by the service via the env-file
      #     template below.
      #   * oidc-<name>-client-secret-hash  — PBKDF2 HASH, mode 0400
      #     owner=authelia-main, consumed by Authelia at startup via
      #     its `template` config-filter (see authelia.nix). This
      #     keeps hash material out of committed Nix entirely.
      sops.secrets =
        let
          routesWithOidc = filterAttrs (_: cfg: cfg.oidc != null) config.nori.lanRoutes;
        in
        (mapAttrs' (
          name: _:
          nameValuePair "oidc-${name}-client-secret" {
            mode = "0440";
            group = "keys";
          }
        ) routesWithOidc)
        // (mapAttrs' (
          name: _:
          nameValuePair "oidc-${name}-client-secret-hash" {
            mode = "0400";
            owner = "authelia-main";
          }
        ) routesWithOidc);

      sops.templates = mapAttrs' (
        name: cfg:
        nameValuePair "oidc-${name}-env" {
          mode = "0440";
          group = "keys";
          content = ''
            ${cfg.oidc.secretEnvName}=${config.sops.placeholder."oidc-${name}-client-secret"}
          '';
        }
      ) (filterAttrs (_: cfg: cfg.oidc != null) config.nori.lanRoutes);
    }
  );
}
