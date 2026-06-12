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
  #   * Caddy vhost reverse-proxying <name>.nori.lan → backend port
  #   * Blocky customDNS mapping <name>.nori.lan → config.nori.lanIp
  #   * Gatus monitor          (if `monitor` is non-null)
  #   * Tailnet firewall hole  (if `exposeOnTailnet`)
  #   * sops raw + hash secrets + env-file template (if `oidc` is set)
  #     — Authelia client list assembly lives in modules/server/
  #     authelia.nix, reading back config.nori.lanRoutes from here.
  #     Hash material stays in sops; the authelia config-filter
  #     injects it at runtime.
  #
  # Service modules declare routing inline alongside their config:
  #
  #   nori.lanRoutes.chat = {
  #     port = 8080;
  #     oidc = {
  #       clientName  = "Open WebUI";
  #       redirectPath = "/oauth/oidc/callback";
  #     };
  #   };

  options.nori.domain = mkOption {
    type = types.str;
    default = "home.phibkro.org";
    description = ''
      Parent DNS domain for the homelab's `*.<domain>` services.
      Single source of truth: vhost names, Authelia cookie domain,
      Authelia issuer URL, OIDC redirect URIs, Caddy ACME wildcard all
      read this rather than hardcoding the literal.

      Split-horizon DNS: Blocky is authoritative for `*.<domain>` on the
      LAN/tailnet (resolves to `nori.lanIp`); public DNS for the same
      names has no A records, so the homelab is reachable only on the
      LAN/tailnet. Caddy obtains real Let's Encrypt certs via DNS-01
      using the existing Cloudflare token in sops, so family devices
      see a green lock with no per-device CA install.

      Renaming requires:
        - Family/operator bookmark updates from old to new domain.
        - Authelia OIDC client redirect URI re-trust (each client
          declared via `nori.lanRoutes.<X>.oidc` re-emits its
          authorized URIs from `''${name}.''${domain}` automatically).
        - Tailscale DNS-search-domain push to include the new domain
          so unqualified hostnames keep resolving on tailnet clients.

      See ADR-0004 for the rationale (pre-existing phibkro.org +
      Cloudflare-hosted DNS made the LE path cheaper than internal CA).
    '';
  };

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
      silently picking workstation.

      Previously the workhorse's tailnet IP, which silently required
      every client to be on tailnet to reach any service — a sharp
      edge for LAN-resident devices that can't or don't run tailscale
      (chromecasts, printers, occasional guest devices). Using the
      LAN IP lets those clients hit services directly. Tailnet
      clients off-LAN still reach the same address via Pi's subnet
      route advertisement (services.tailscale.useRoutingFeatures =
      "server" in machines/pi/default.nix); the client side needs
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
            description = ''
              Backend host for Caddy to proxy to. Legacy / fallback —
              prefer `runsOn` for cross-host placement. Generators use
              `runsOn`-derived host if set, this field otherwise.
            '';
          };
          runsOn = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "aurora";
            description = ''
              Name of the homelab host that runs this route's backend
              service (matches a `nori.hosts.<name>` registry key).
              Generators resolve to:
                * `127.0.0.1` when `runsOn` matches the host evaluating
                  the route (Caddy proxies to the local loopback)
                * `config.nori.hosts.<runsOn>.tailnetIp` otherwise
                  (Caddy proxies cross-host over tailnet)
              Falls back to the legacy `host` field when null.

              This is the mechanism that lets route declarations live
              outside the `mkIf cfg.enabled` gate in each service module
              — every host that imports the module sees the route in
              `nori.lanRoutes`, but the backend resolves to the right
              address per host. Encodes the pi-central entry plane
              shape: pi's Caddy serves every route; backends live on
              whichever host fits (workhorse vs always-on vault).
            '';
          };
          scheme = mkOption {
            type = types.enum [
              "http"
              "https"
            ];
            default = "http";
            description = "Backend scheme. Most services run plain HTTP; Caddy terminates TLS.";
          };
          upstreamHostHeader = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "127.0.0.1:9119";
            description = ''
              Optional rewrite of the `Host` request header before
              forwarding to the upstream. By default Caddy forwards
              the original Host (the public `<n>.nori.lan`), which
              most backends accept. Set this when the backend
              validates Host as a DNS-rebinding defence and rejects
              anything other than its bind address — Hermes' dashboard
              is the canonical case: it binds to 127.0.0.1:9119 and
              rejects requests whose Host header isn't a loopback name.
            '';
          };
          upstreamOriginHeader = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "http://127.0.0.1:9119";
            description = ''
              Optional rewrite of the `Origin` header before forwarding
              WebSocket / fetch upgrade requests. Paired companion to
              `upstreamHostHeader`: apps that validate `Host` against
              their bind address as a DNS-rebinding defence usually
              run the same check on the WebSocket `Origin` field too
              (since FastAPI HTTP middleware doesn't fire for WS
              upgrades, the check is re-implemented at the WS handler).
              Hermes' embedded chat PTY is the canonical case —
              without this rewrite, the chat WebSocket upgrade refuses
              with `origin_mismatch origin=https://… bound=127.0.0.1`.
            '';
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
          audience = mkOption {
            type = types.enum [
              "operator"
              "family"
              "public"
            ];
            default = "operator";
            description = ''
              Who this route is for. Documents intent + drives the
              auth-stacking principle:

                * operator — admin-only management UIs (the *arr stack,
                  qBittorrent, Beszel admin, Syncthing). Tailnet
                  membership IS the auth; layering Authelia on top
                  duplicates the network-perimeter guarantee for no
                  per-user-state value, while making Authelia uptime
                  load-bearing for operator workflows.

                * family — services with per-user state inside the app
                  (Jellyfin watch progress, Immich photos, Jellyseerr
                  request history, Open WebUI chat, Vaultwarden vaults,
                  Navidrome playlists). Native OIDC propagates the
                  user identity into the app — that's the value-add.
                  Where native OIDC isn't clean (Komga, calibre-web),
                  forward-auth gates browser access at Caddy.

                * public — intentionally open dashboards (home/Glance,
                  status/Gatus) and the SSO portal itself (auth/
                  Authelia). Tailnet trust is the only gate; auth
                  inside these would defeat their purpose.

              Currently informational; future flake checks may assert
              consistency (e.g., audience=family without an oidc/
              forwardAuth block warns).
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
                      "Projects"
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
          forwardAuth = mkOption {
            default = null;
            description = ''
              If set, gate this route via Authelia forward-auth at the
              Caddy layer. Caddy asks Authelia's `/api/verify` whether
              the request's session cookie is valid before forwarding;
              if not, Authelia issues a 302 to the portal. The session
              cookie at *.nori.lan covers every forward-auth'd route —
              log in once at https://auth.nori.lan, navigate to any
              gated service without re-auth.

              Used for services that don't have native OIDC client
              support (the *arr stack, qBittorrent). Trade vs `oidc`:
                * `oidc`         — per-user identity inside the app;
                                    requires the app to support OIDC.
                * `forwardAuth`  — uniform Authelia gate at Caddy; the
                                    app sees only the proxy, no per-user
                                    identity propagated. Works for any
                                    HTTP service.

              `exemptPaths` lets app-to-app API calls (Sonarr → Prowlarr,
              Bazarr → Sonarr) bypass the auth check — those flows use
              the app's own API key, not the user session, and would
              break under cookie-based forward-auth.

              Authelia uptime becomes load-bearing: an Authelia outage
              returns 502 for every forward-auth'd route. SSH-tunnel to
              the backend port directly as the recovery escape hatch.
              See modules/server/authelia.nix for the upstream.
            '';
            type = types.nullOr (
              types.submodule {
                options = {
                  exemptPaths = mkOption {
                    type = types.listOf types.str;
                    default = [ "/api/*" ];
                    description = ''
                      Path globs that bypass forward-auth. Format is
                      Caddy path-matcher syntax (`/api/*`, `/api/v3/*`,
                      etc.). Default `/api/*` covers the *arr stack and
                      most other apps that namespace their API.
                      Override per-service when the API path is
                      non-standard.
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
              Mutually exclusive in practice with `forwardAuth` —
              prefer `oidc` when the app supports it (per-user
              identity), `forwardAuth` otherwise.
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
      forwardAuthRoutes = filterAttrs (_: r: r.forwardAuth != null) routes;

      # Resolve a route's backend host. `runsOn` (the placement field)
      # wins when set: 127.0.0.1 if the route runs on the evaluating
      # host, the runsOn host's tailnet IP otherwise. Falls back to the
      # legacy `host` field (default 127.0.0.1) when runsOn is null —
      # routes that haven't migrated to the lift refactor see no change.
      myHost = config.networking.hostName;
      routeHost =
        cfg:
        if cfg.runsOn == null then
          cfg.host
        else if cfg.runsOn == myHost then
          "127.0.0.1"
        else
          config.nori.hosts.${cfg.runsOn}.tailnetIp;
      autheliaEnabled =
        config.services.authelia.instances != { }
        && lib.any (i: i.enable) (lib.attrValues config.services.authelia.instances);
      # Caddy on this host actually consumes the forwardAuth blocks. If
      # Caddy isn't enabled, the routes are just data — no proxying
      # happens, so the Authelia dependency doesn't bite. Hosts that
      # only import the bundle for the route registry shouldn't trip
      # the assertion.
      caddyEnabledHere = config.services.caddy.enable;
    in
    {
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
        {
          assertion = !caddyEnabledHere || forwardAuthRoutes == { } || autheliaEnabled;
          message = ''
            nori.lanRoutes with `forwardAuth` set require Authelia to be
            running on the same host (Caddy hits 127.0.0.1:9091 for the
            auth check). Routes with forwardAuth: ${lib.concatStringsSep ", " (lib.attrNames forwardAuthRoutes)}.

            Either drop the forwardAuth blocks, or import
            modules/server/authelia.nix on this host.
          '';
        }
        {
          assertion = lib.all (r: !(r.oidc != null && r.forwardAuth != null)) (lib.attrValues routes);
          message = ''
            nori.lanRoutes.<n> sets BOTH `oidc` and `forwardAuth`.
            These are mutually exclusive — `oidc` lets the app handle
            login per-user; `forwardAuth` gates the route at Caddy with
            no app-side awareness. Pick one. Conflicting routes:
              ${lib.concatStringsSep ", " (
                lib.attrNames (lib.filterAttrs (_: r: r.oidc != null && r.forwardAuth != null) routes)
              )}
          '';
        }
      ];

      # Single wildcard vhost matching `*.<nori.domain>`. Inside, per-
      # route `@host` matchers + `handle` blocks route each subdomain
      # to its backend. Why one block instead of per-route vhosts:
      # Caddy issues one cert per vhost name by default, so 30 vhosts
      # = 30 separate ACME flows = thousands of CF API calls every
      # renewal cycle. A single wildcard cert (`*.<nori.domain>`)
      # covers every subdomain in ONE issuance and ONE renewal — the
      # ACME volume drops by 30× and rate-limit risk effectively
      # disappears. Wildcards require DNS-01 (which we already use).
      services.caddy.virtualHosts."*.${config.nori.domain}".extraConfig =
        let
          routes = config.nori.lanRoutes;
          # Per-route handle block: `@<name> host <name>.<domain>` + handle.
          # forwardAuth is per-route, so its block lives inside the handle.
          routeBlock =
            name: cfg:
            let
              headerLines = lib.concatStringsSep "\n          " (
                lib.optional (cfg.upstreamHostHeader != null) "header_up Host ${cfg.upstreamHostHeader}"
                ++ lib.optional (cfg.upstreamOriginHeader != null) "header_up Origin ${cfg.upstreamOriginHeader}"
              );
              headerBlock = lib.optionalString (headerLines != "") ''
                 {
                  ${headerLines}
                }'';
              backend = "reverse_proxy ${cfg.scheme}://${routeHost cfg}:${toString cfg.port}${headerBlock}";
              faBlock = lib.optionalString (cfg.forwardAuth != null) ''
                @${name}AuthNeeded {
                  host ${name}.${config.nori.domain}
                  not path ${lib.concatStringsSep " " cfg.forwardAuth.exemptPaths}
                }
                forward_auth @${name}AuthNeeded http://127.0.0.1:9091 {
                  uri /api/verify?rd=https://auth.${config.nori.domain}
                  copy_headers Remote-User Remote-Email Remote-Name Remote-Groups
                }
              '';
            in
            ''
              @${name} host ${name}.${config.nori.domain}
              handle @${name} {
                ${faBlock}${backend}
              }
            '';
        in
        lib.concatStringsSep "\n" (lib.mapAttrsToList routeBlock routes);

      services.blocky.settings.customDNS.mapping =
        # Primary mapping — every route name under the new domain.
        (mapAttrs' (
          name: _: nameValuePair "${name}.${config.nori.domain}" config.nori.lanIp
        ) config.nori.lanRoutes)
        # Transitional mapping — keep `*.nori.lan` resolving so old
        # bookmarks land at Caddy's redirect vhost (in caddy.nix), which
        # 301s them to the new domain. Drop this block when family
        # devices have all migrated bookmarks. Until then, every route
        # gets a parallel `<name>.nori.lan` entry pointing at the same IP.
        // (mapAttrs' (name: _: nameValuePair "${name}.nori.lan" config.nori.lanIp) config.nori.lanRoutes);

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
          url = "${cfg.scheme}://${routeHost cfg}:${toString cfg.port}${cfg.monitor.path}";
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
        # Raw client secrets: emitted on any host that has routes
        # declared, since service modules read them on the host where
        # the BACKEND runs (via `EnvironmentFile` from the sops template
        # below). Owned by the `keys` group; consuming services join
        # that group via `SupplementaryGroups`.
        (mapAttrs' (
          name: _:
          nameValuePair "oidc-${name}-client-secret" {
            mode = "0440";
            group = "keys";
          }
        ) routesWithOidc)
        # PBKDF2 hashes: only emit on hosts that run Authelia (the user
        # `authelia-main` only exists there). Other hosts importing the
        # bundle for the route registry don't need the hash material.
        // (lib.optionalAttrs autheliaEnabled (
          mapAttrs' (
            name: _:
            nameValuePair "oidc-${name}-client-secret-hash" {
              mode = "0400";
              owner = "authelia-main";
            }
          ) routesWithOidc
        ));

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
