{ config, lib, ... }:

/**
  Networking concern — the lan-route registry + its adapters.

  `default.nix` carries `nori.lanRoutes` (schema + collection +
  Caddy vhost / Blocky DNS / Gatus monitor / Authelia OIDC-secret
  generators). Adapter siblings:

   - `caddy.nix`        — Caddy reverse-proxy daemon
   - `blocky.nix`       — Blocky DNS daemon (authoritative for
                          `*.${domain}` on LAN/tailnet)
   - `gatus-probe.nix`  — per-route monitor schema fragment
                          (consumed inline by lan-route)

  Authelia (the OIDC daemon) is access-concern, not networking;
  lives at `modules/infra/access/` (Phase 3d). lan-route generates
  the sops-templated OIDC secrets here; authelia consumes them.

  ## Three zones, default-deny

  | Zone | What's there | Default posture |
  |---|---|---|
  | **localhost** | Services bind here unless explicitly exposed | Closed to outside |
  | **tailnet** | Personal devices + family. SSH, Samba, `*.${domain}` HTTPS, direct service ports | Closed by default; Caddy on 80+443 + Samba on 445 are the only globally-open tailnet ports |
  | **public internet** | Personal apps that need public exposure live at Cloudflare edge (Pages + Workers + D1) | **Homelab serves nothing publicly** by default. Tailscale Funnel is the prototyped path if anything ever needs to land public traffic |

  The Cloudflare edge apps (phibkro.org apex, filmder, drinks-app,
  finnbydel-app, heim) live as Pages (static) + Workers+D1 (stateful).
  The homelab keeps tailnet-only copies of `filmder` + `heim` via
  `nori.lanRoutes` for fast internal access. A `cloudflared` Tunnel
  approach was decommissioned 2026-05-08.

  ## DNS architecture

  ```mermaid
  flowchart LR
      device[tailnet device] -->|DNS query| ts[Tailscale stub 100.100.100.100]
      ts -->|global-nameserver push| pi_blocky[Pi Blocky · authoritative]
      pi_blocky -->|"*.${nori.domain}"| host_map["*.${nori.domain} → pi LAN IP<br/>auto-generated from nori.lanRoutes"]
      pi_blocky -->|other| upstream[1.1.1.1 / 9.9.9.9]
      classDef primary fill:#3a5,stroke:#2a4,color:#fff
      class pi_blocky primary
  ```

  Pi runs Blocky in **self-hosted mode** — auto-generates the
  `*.${domain}` customDNS map from `nori.lanRoutes` (every route
  name resolves to pi's LAN IP, since pi is the Caddy host).
  Tailscale's global-nameserver push points tailnet devices at pi.
  LAN-only devices (smart TV, guest phones) are NOT covered — they
  keep using whatever the router pushes. Workstation's Blocky is
  also self-hosted as a fallback secondary (resolves the same map;
  LAN-side resilience for if pi is down).

  Why Tailscale push, not router DHCP: the ISP-shipped Genexis EG400
  locks DHCP DNS settings out of the user-facing admin UI. Router-
  side DNS replacement requires either bridge-mode activation by
  phone request + a second router, or double-NAT with a downstream
  router. Neither set up; Tailscale push is the zero-hardware-cost
  workaround.

  **Bootstrap loop hazard:** workstation's `/etc/resolv.conf` points
  at Tailscale's stub (100.100.100.100); Tailscale forwards back to
  workstation's Blocky; Blocky can't resolve its own outbound URLs
  (blocklist sources, DoH endpoints) before serving DNS.
  `services.blocky.settings.bootstrapDns` MUST be set to direct
  upstream IPs. Codified in `.claude/skills/gotcha-blocky-bootstrap-
  loop/`.

  ## Caddy + TLS + naming

  Caddy terminates TLS for every `<name>.${domain}` with a
  **Let's Encrypt wildcard cert** (`*.${domain}`) obtained via ACME
  DNS-01 against Cloudflare. The wildcard avoids per-vhost issuance
  + the LE rate-limit storm that would follow. ISRG roots ship pre-
  trusted on every modern device — no per-device CA install, no Mac
  keychain dance, no Node `NODE_EXTRA_CA_CERTS` env var. See
  ADR-0004 for the rationale.

  The Cloudflare API token lives in sops (`cloudflare_acme_token`);
  Caddy's `withPlugins` bakes in `caddy-dns/cloudflare`. The
  `nori.domain` option is the single source of truth — every vhost
  name, Authelia cookie domain + issuer URL, and OIDC redirect URI
  reads from it.

  Transitional `*.nori.lan` redirect: pi's Caddy still serves
  `*.nori.lan` (Caddy internal CA) and 301-redirects to the same
  path under `home.phibkro.org`. Drop this block from `caddy.nix` +
  the parallel entries in `blocky` customDNS once family bookmarks
  have migrated.

  ## Naming: function over brand

  `chat.${domain}` not `open-webui.${domain}`. `media` not
  `jellyfin`. The brand changes (Uptime Kuma → Gatus); the function
  doesn't. Brand-named only when the brand IS the identity (`auth`
  for Authelia, `samba`). Enforced by the
  `lint.functionNamedSubdomains` TOML rule.
*/
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
  imports = [
    ./gatus-probe.nix
    ./caddy.nix
    ./blocky.nix
  ];

  /**
    `nori.lanRoutes` — single source of truth for services exposed
    under `*.${domain}`. Each entry generates ALL of:

     - Caddy vhost reverse-proxying `<name>.<domain>` → backend port
     - Blocky customDNS mapping `<name>.<domain>` → `config.nori.lanIp`
     - Gatus monitor (if `monitor` is non-null)
     - Tailnet firewall hole (if `exposeOnTailnet`)
     - sops raw + hash secrets + env-file template (if `oidc` is
       set) — Authelia client list assembly lives in
       `modules/infra/access/authelia.nix`, reading back
       `config.nori.lanRoutes` from here. Hash material stays in
       sops; the authelia config-filter injects it at runtime.

    Service modules declare routing inline alongside their config:

    ```nix
    nori.lanRoutes.chat = {
      port = 8080;
      oidc = {
        clientName  = "Open WebUI";
        redirectPath = "/oauth/oidc/callback";
      };
    };
    ```
  */

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
      and a non-null lanIp" (see modules/infra/hosts.nix). When
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
      "server" in modules/machines/pi/default.nix); the client side needs
      --accept-routes set in its tailscaled config.

      Consumers: Blocky's forwarder mode (modules/infra/networking/blocky.nix)
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
          runsOn = mkOption {
            type = types.str;
            example = "aurora";
            description = ''
              Name of the homelab host that runs this route's backend
              service (matches a `nori.hosts.<name>` registry key).
              Generators resolve to:
                * `127.0.0.1` when `runsOn` matches the host evaluating
                  the route (Caddy proxies to the local loopback)
                * `config.nori.hosts.<runsOn>.tailnetIp` otherwise
                  (Caddy proxies cross-host over tailnet)

              This is the mechanism that lets route declarations live
              outside the `mkIf cfg.enabled` gate in each service module
              — every host that imports the module sees the route in
              `nori.lanRoutes`, but the backend resolves to the right
              address per host. Encodes the pi-central entry plane
              shape: pi's Caddy serves every route; backends live on
              whichever host fits (workhorse vs always-on vault).

              Why location-policy is coupled with route registration
              here, not extracted: location is implicit-from-import-site
              for host-confined services; it becomes explicit only when
              a service crosses machines, which IS the act of declaring
              an HTTP route. The three concerns (service / route /
              location) degenerate at host-local and unify at
              cross-machine. See
              `docs/reports/2026-06-17-runson-coupling-analysis.md`
              for the full analysis + algebraic forward-extension
              (failover / loadbalance / sequential).
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
              Open the backend port to EVERY tailnet peer, bypassing Caddy.
              Default closed — Caddy on 443 is the canonical entry point.

              You do NOT need this for cross-host routing: the entry-plane
              Caddy reaches every backend automatically via an
              appliance-scoped firewall rule (see the firewall block below).
              Opt in only when something OTHER than Caddy needs direct port
              access for ALL peers (legacy clients, programmatic tools that
              don't handle Caddy's internal CA).

              Forbidden on `family`/`public`-via-OIDC routes: direct access
              defeats the per-user auth Caddy fronts (assertion below). For
              direct access scoped to a specific peer (e.g. an agent host),
              add a service-local `firewall.extraInputRules` instead — see
              modules/services/ollama.nix.
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

              Enforced (eval-time assertion below): audience=family
              requires either an `oidc` or `forwardAuth` block, or
              an explicit `noAuthReason` string naming why neither
              fits.
            '';
          };
          noAuthReason = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "CalDAV clients can't follow forward-auth redirects";
            description = ''
              Set to a one-line reason when audience=family but neither
              `oidc` nor `forwardAuth` applies. Forces the operator to
              name why; forces future readers to see it. Empty string
              is invalid — set it or set one of the auth blocks.

              Legitimate today:
                * radicale  — CalDAV/CardDAV clients can't follow
                              forward-auth redirects (htpasswd-only)
                * jellyfin  — mobile/TV clients bypass cookie-based
                              forward-auth; native SSO plugin has
                              sharp historical edges
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
                    description = ''
                      How often Gatus runs the probe. systemd-style
                      duration string (`60s`, `5m`, `1h`).
                    '';
                  };
                  failureThreshold = mkOption {
                    type = types.int;
                    default = 3;
                    description = ''
                      Consecutive failed probes before Gatus fires an
                      alert. 3 absorbs transient blips without delaying
                      a real outage long.
                    '';
                  };
                  conditions = mkOption {
                    type = types.listOf types.str;
                    default = [ "[STATUS] == 200" ];
                    description = ''
                      Gatus condition expressions (see
                      <https://gatus.io/docs/conditions>). Each must
                      hold for the probe to pass. Default checks HTTP
                      status; override for richer probes (header
                      match, body regex, response time).
                    '';
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
              See modules/infra/access/authelia.nix for the upstream.
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
                  modules/infra/access/authelia.nix from this declaration)
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

      /*
        Resolve a route's backend host. `runsOn` (the placement field)
        wins when set: 127.0.0.1 if the route runs on the evaluating
        host, the runsOn host's tailnet IP otherwise.
      */
      myHost = config.networking.hostName;
      routeHost =
        cfg: if cfg.runsOn == myHost then "127.0.0.1" else config.nori.hosts.${cfg.runsOn}.tailnetIp;
      autheliaEnabled =
        config.services.authelia.instances != { }
        && lib.any (i: i.enable) (lib.attrValues config.services.authelia.instances);
      /*
        Caddy on this host actually consumes the forwardAuth blocks. If
        Caddy isn't enabled, the routes are just data — no proxying
        happens, so the Authelia dependency doesn't bite. Hosts that
        only import the bundle for the route registry shouldn't trip
        the assertion.
      */
      caddyEnabledHere = config.services.caddy.enable;

      /*
        Hosts running the HTTP entry plane. `role == "appliance"` IS the
        declared "runs Caddy" fact (nori.hosts role enum) — single source of
        truth, no hardcoded 100.x. A cross-host backend must admit these — and
        only these — on the tailnet so the entry-plane Caddy can reverse-proxy
        it, while other tailnet peers cannot reach the backend directly (and so
        cannot bypass the route's `audience` auth). Self is excluded: when the
        backend IS on an appliance, Caddy reaches it via loopback, no tailnet
        hole needed.
      */
      applianceReachIps = lib.mapAttrsToList (_: h: h.tailnetIp) (
        lib.filterAttrs (name: h: h.role == "appliance" && name != myHost) config.nori.hosts
      );
      # Routes whose backend runs on THIS host — the only ports we open here
      # (a port with no local listener is dead firewall surface).
      localRoutes = lib.filterAttrs (_: cfg: cfg.runsOn == myHost) config.nori.lanRoutes;
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
          assertion = lib.all (n: builtins.hasAttr routes.${n}.runsOn config.nori.hosts) names;
          message =
            let
              unknown = lib.filter (n: !(builtins.hasAttr routes.${n}.runsOn config.nori.hosts)) names;
            in
            ''
              nori.lanRoutes.<n>.runsOn must reference a host declared
              in nori.hosts (the placement registry). Caught at eval
              instead of as an opaque `attribute '<typo>' missing`
              error when caddy/dashboards walk the route at build time.

              Offending routes: ${
                lib.concatStringsSep ", " (map (n: "${n} (runsOn=${routes.${n}.runsOn})") unknown)
              }
              Known hosts: ${lib.concatStringsSep ", " (lib.attrNames config.nori.hosts)}
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
            modules/infra/access/authelia.nix on this host.
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
        {
          assertion = lib.all (
            r: r.audience != "family" || r.oidc != null || r.forwardAuth != null || r.noAuthReason != null
          ) (lib.attrValues routes);
          message = ''
            nori.lanRoutes.<n> with audience="family" carries per-user
            state and needs identity beyond tailnet membership. Set one of:
              * oidc = { ... }        (preferred — per-user identity in-app)
              * forwardAuth = { ... } (Caddy-gate when the app can't OIDC)
              * noAuthReason = "..."  (legitimate exception; document why)
            …or downgrade audience to "operator" if tailnet auth suffices.

            Routes missing all three:
              ${lib.concatStringsSep ", " (
                lib.attrNames (
                  lib.filterAttrs (
                    _: r: r.audience == "family" && r.oidc == null && r.forwardAuth == null && r.noAuthReason == null
                  ) routes
                )
              )}
          '';
        }
      ];

      /*
        Single wildcard vhost matching `*.<nori.domain>`. Inside, per-
        route `@host` matchers + `handle` blocks route each subdomain
        to its backend. Why one block instead of per-route vhosts:
        Caddy issues one cert per vhost name by default, so 30 vhosts
        = 30 separate ACME flows = thousands of CF API calls every
        renewal cycle. A single wildcard cert (`*.<nori.domain>`)
        covers every subdomain in ONE issuance and ONE renewal — the
        ACME volume drops by 30× and rate-limit risk effectively
        disappears. Wildcards require DNS-01 (which we already use).
      */
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
        /*
          Transitional mapping — keep `*.nori.lan` resolving so old
          bookmarks land at Caddy's redirect vhost (in caddy.nix), which
          301s them to the new domain. Drop this block when family
          devices have all migrated bookmarks. Until then, every route
          gets a parallel `<name>.nori.lan` entry pointing at the same IP.
        */
        // (mapAttrs' (name: _: nameValuePair "${name}.nori.lan" config.nori.lanIp) config.nori.lanRoutes);

      /*
        Tailnet firewall — two openings, separated by intent:

          1. Caddy-reach (automatic, appliance-scoped). Every backend on
             this host admits the appliance host(s) by SOURCE IP so the
             entry-plane Caddy can reverse-proxy it over the tailnet. Other
             tailnet peers cannot reach the backend directly → a route's
             `audience` gate (Authelia/OIDC for family) cannot be bypassed
             by curling the backend port. This is what every cross-host
             route actually needs; it used to be smuggled in via
             `exposeOnTailnet`, conflating Caddy-reach with all-peer access.

          2. Direct all-peer access (opt-in via `exposeOnTailnet`). Opens
             the port to EVERY tailnet peer, bypassing Caddy — for the rare
             legacy-client / programmatic case. Forbidden on `family`
             audience (assertion below): direct access defeats per-user auth.

        Both filter to `runsOn == hostName` (a port with no local listener is
        dead surface) and align with default-deny (Caddy :80/:443 is the
        canonical entry).
      */
      networking.firewall.extraInputRules = lib.concatStringsSep "\n" (
        lib.flatten (
          lib.mapAttrsToList (
            _: cfg:
            map (
              ip: ''iifname "tailscale0" ip saddr ${ip} tcp dport ${toString cfg.port} accept''
            ) applianceReachIps
          ) localRoutes
        )
      );
      networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.flatten (
        lib.mapAttrsToList (_: cfg: lib.optional cfg.exposeOnTailnet cfg.port) localRoutes
      );

      /*
        Auto-generated Gatus endpoints for routes that opt in via
        `monitor`. Manual entries in modules/infra/observability/gatus.nix
        (blocky-dns, samba-smb) coexist via list concatenation.
      */
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

      /**
        OIDC plumbing for routes with `oidc` set. The Authelia client
        entry is assembled by modules/infra/access/authelia.nix reading
        config.nori.lanRoutes — keeps single ownership of the clients
        list (NixOS module merging on freeform-typed lists conflicts
        rather than concatenates, so a centralized assembly site is
        cleaner than mkMerge from multiple modules).

        Two sops secrets per OIDC route:
          * oidc-<name>-client-secret       — RAW secret, mode 0440
            group=keys, consumed by the service via the env-file
            template below.
          * oidc-<name>-client-secret-hash  — PBKDF2 HASH, mode 0400
            owner=authelia-main, consumed by Authelia at startup via
            its `template` config-filter (see authelia.nix). This
            keeps hash material out of committed Nix entirely.
      */
      sops.secrets =
        let
          routesWithOidc = filterAttrs (_: cfg: cfg.oidc != null) config.nori.lanRoutes;
        in
        /*
          Raw client secrets: emitted on any host that has routes
          declared, since service modules read them on the host where
          the BACKEND runs (via `EnvironmentFile` from the sops template
          below). Owned by the `keys` group; consuming services join
          that group via `SupplementaryGroups`.
        */
        (mapAttrs' (
          name: _:
          nameValuePair "oidc-${name}-client-secret" {
            mode = "0440";
            group = "keys";
          }
        ) routesWithOidc)
        /*
          PBKDF2 hashes: only emit on hosts that run Authelia (the user
          `authelia-main` only exists there). Other hosts importing the
          bundle for the route registry don't need the hash material.
        */
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
