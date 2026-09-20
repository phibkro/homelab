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
  lives at `services/authelia/nixos.nix`. lan-route generates
  the sops-templated OIDC secrets here; authelia consumes them.

  ## Three zones, default-deny

  | Zone | What's there | Default posture |
  |---|---|---|
  | **localhost** | Services bind here unless explicitly exposed | Closed to outside |
  | **tailnet** | Personal devices + operator workflows. SSH, Samba, `*.${domain}` HTTPS, direct service ports | Closed by default; Caddy on 80+443 + Samba on 445 are the only globally-open tailnet ports |
  | **public internet** | Explicitly selected family services plus Cloudflare-edge personal apps | Homelab routes stay internal by default; `reachability = "internet"` opts in one account-gated route at a time |

  The Cloudflare edge apps (phibkro.org apex, filmder, drinks-app,
  finnbydel-app, heim) live as Pages (static) + Workers+D1 (stateful).
  The homelab keeps internal copies of `filmder` + `heim` via
  `nori.lanRoutes` for fast access. Family media routes may opt into
  direct internet reachability through the Pi entry plane; every other
  route remains limited to LAN/tailnet client ranges even if a caller
  guesses its hostname or forges its Host header.

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
  upstream IPs. Codified in `Mnemopi recall: gotcha-blocky-bootstrap-dns`.

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

  Transitional domains declared by `nori.inventory.site.deprecatedDomains`
  remain in Blocky and receive an HTTP 301 from Caddy to the canonical domain.
  Remove a domain from inventory once family bookmarks have migrated.

  ## Naming: function over brand

  `chat.${domain}` not `open-webui.${domain}`. `media` not
  `jellyfin`. The brand changes (Uptime Kuma → Gatus); the function
  doesn't. Brand-named only when the brand IS the identity (`auth`
  for Authelia, `samba`). Enforced by the
  `lint.functionNamedSubdomains` TOML rule.
*/
let
  audienceKeys = (import ../../../roles/audiences.nix).keys;
  site = import ../../../inventory/site.nix;
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
    ./gatus-probes.nix
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
       `services/authelia/nixos.nix`, reading back
       `config.nori.lanRoutes` from here. Hash material stays in
       sops; the authelia config-filter injects it at runtime.

    Service modules declare routing inline alongside their config:

    ```nix
    nori.lanRoutes.chat = {
      port = 8080;
      oidc = {
        clientName  = "Open WebUI";
        redirectPath = "/oauth/oidc/callback";
        tokenEndpointAuthMethod = "client_secret_basic";
      };
    };
    ```
  */

  options.nori.domain = mkOption {
    type = types.str;
    default = (import ../../../inventory/site.nix).domain;
    description = ''
      Parent DNS domain for the homelab's `*.<domain>` services.
      Single source of truth: vhost names, Authelia cookie domain,
      Authelia issuer URL, OIDC redirect URIs, Caddy ACME wildcard all
      read this rather than hardcoding the literal.

      Split-horizon DNS: Blocky is authoritative for `*.<domain>` on the
      LAN/tailnet (resolves to `nori.lanIp`). Public DNS contains records
      only for routes whose `reachability` is explicitly `internet`;
      `services/cloudflare-ddns/nixos.nix` reconciles
      those exact, DNS-only IPv4 records to the residential WAN address.
      All other names remain internal. Caddy obtains real Let's Encrypt
      certs via DNS-01 using the existing Cloudflare token in sops, so
      family devices see a green lock with no per-device CA install.

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
        candidates = lib.filterAttrs (
          _: h: h.role == "workhorse" && h.lanIp != null
        ) config.nori.inventory.hosts;
        names = lib.attrNames candidates;
      in
      if lib.length names == 1 then
        (lib.head (lib.attrValues candidates)).lanIp
      else
        throw ''
          nori.lanIp: cannot pick a default — expected exactly one workhorse
          host with a non-null lanIp in the registry, found ${toString (lib.length names)}
          (${lib.concatStringsSep ", " names}). Set nori.lanIp explicitly,
          or update the host registry (`inventory/hosts.nix`).
        '';
    defaultText = lib.literalExpression ''
      # the unique workhorse-with-lanIp from config.nori.hosts;
      # eval-fails if zero or more than one matches.
    '';
    description = ''
      LAN IP that service-domain names resolve to. Derived from the
      nori.hosts registry as "the unique host with role=workhorse
      and a non-null lanIp" (see infra/common/nixos/hosts.nix). When
      a future second workhorse with a static LAN lease lands, the
      derivation fails eval — surfaces the ambiguity instead of
      silently picking workstation.

      Previously the workhorse's tailnet IP, which silently required
      every client to be on tailnet to reach any service — a sharp
      edge for LAN-resident devices that can't or don't run tailscale
      (chromecasts, printers, occasional guest devices). Using the
      LAN IP lets those clients hit services directly. Tailnet
      clients off-LAN still reach the same address via Pi's Ansible-managed
      subnet route advertisement (`services/tailscale/ansible`); the client side needs
      --accept-routes set in its tailscaled config.

      Consumers: Blocky's forwarder mode (services/blocky/nixos.nix)
      and the Blocky DNS generator below. Both want a single "where
      does the service namespace live" address.
    '';
  };


  config = mkIf (config.nori.inventory.routes != { }) (
    let
      routes = config.nori.inventory.routes;
      ports = lib.mapAttrsToList (_: r: r.port) routes;
      names = lib.attrNames routes;
      oidcRoutes = filterAttrs (_: r: r.oidc != null) routes;
      localOidcRoutes = filterAttrs (
        _: r: r.oidc != null && r.host == config.nori.inventory.currentHost
      ) routes;
      forwardAuthRoutes = filterAttrs (_: r: r.forwardAuth != null) routes;
      internetIdentityRoutes = filterAttrs (
        _: r: r.reachability == "internet" && (r.oidc != null || r.forwardAuth != null)
      ) routes;
      myHost = config.nori.inventory.currentHost;
      routeHost =
        cfg:
        if cfg.host == myHost then "127.0.0.1" else config.nori.inventory.hosts.${cfg.host}.tailnetIp;
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
    in
    {
      assertions = [
        {
          assertion = lib.length ports == lib.length (lib.unique ports);
          message = "nori.inventory.routes have duplicate backend ports.";
        }
        {
          assertion = lib.all (n: builtins.hasAttr routes.${n}.host config.nori.inventory.hosts) names;
          message = "nori.inventory.routes reference an unknown backend host.";
        }
        {
          assertion = lib.all (n: builtins.match "[a-z][a-z0-9-]*" n != null) names;
          message = "nori.inventory.routes names must be DNS-safe.";
        }
        {
          assertion = lib.all (r: lib.hasPrefix "/" r.oidc.redirectPath) (lib.attrValues oidcRoutes);
          message = "nori.inventory.routes OIDC redirect paths must begin with '/'.";
        }
        {
          assertion = !caddyEnabledHere || forwardAuthRoutes == { } || autheliaEnabled;
          message = "nori.inventory.routes with forwardAuth require local Authelia when Caddy is enabled.";
        }
        {
          assertion = lib.all (r: !(r.oidc != null && r.forwardAuth != null)) (lib.attrValues routes);
          message = "nori.inventory.routes cannot set both oidc and forwardAuth.";
        }
        {
          assertion = lib.all (r: !r.publicStatus || (r.monitor != null && r.audience != "operator")) (
            lib.attrValues routes
          );
          message = "Public status routes must be monitored and non-operator.";
        }
        {
          assertion = lib.all (r: r.reachability != "internet" || r.audience != "operator") (
            lib.attrValues routes
          );
          message = "Internet routes cannot use the operator audience.";
        }
        {
          assertion =
            internetIdentityRoutes == { } || (routes ? auth && routes.auth.reachability == "internet");
          message = "Internet routes using identity require an internet-reachable auth route.";
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
          # Per-route handle block: `@<name>` combines the hostname with
          # the declared reachability boundary. forwardAuth is per-route,
          # so its block lives inside the handle.
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
                  host ${cfg.hostname}
                  not path ${lib.concatStringsSep " " cfg.forwardAuth.exemptPaths}
                }
                forward_auth @${name}AuthNeeded http://127.0.0.1:9091 {
                  uri /api/verify?rd=https://auth.${config.nori.domain}
                  copy_headers Remote-User Remote-Email Remote-Name Remote-Groups
                }
              '';
              matcherLines = lib.concatStringsSep "\n        " (
                [ "host ${name}.${config.nori.domain}" ]
                ++ lib.optional (cfg.reachability == "internal") "client_ip private_ranges 100.64.0.0/10"
              );
            in
            ''
              @${name} {
                ${matcherLines}
              }
              handle @${name} {
                ${faBlock}${backend}
              }
            '';
        in
        ''
          # Tailscale Funnel owns the tailnet address's :443 listener; Caddy
          # serves LAN and subnet-routed clients on the appliance address.
          bind ${config.nori.lanIp}
        ''
        + lib.concatStringsSep "\n" (lib.mapAttrsToList routeBlock routes)
        + ''

          # Unknown or network-ineligible hosts fail closed. This catch-all
          # is load-bearing once WAN :443 is forwarded to the Pi.
          handle {
            respond 404
          }
        '';

      services.blocky.settings.customDNS.mapping =
        # Primary mapping — every route name under the canonical domain.
        (mapAttrs' (
          _name: cfg: nameValuePair cfg.hostname config.nori.lanIp
        ) routes)
        /*
          Transitional mapping — keep `*.nori.lan` resolving so old
          bookmarks land at Caddy's redirect vhost (in caddy.nix), which
          301s them to the new domain. Drop this block when family
          devices have all migrated bookmarks. Until then, every route
          gets a parallel `<name>.nori.lan` entry pointing at the same IP.
        */
        // lib.foldl' (
          aliases: domain:
          aliases
          // mapAttrs' (name: _: nameValuePair "${name}.${domain}" config.nori.lanIp) routes
        ) { } site.deprecatedDomains;

      /*
        Tailnet firewall: open backend ports for opt-in routes only,
        AND only on the host that actually runs the backend. Without
        the `runsOn == hostName` filter, every host that imports the
        bundle opens every exposed port — harmless when no listener
        responds, but a wider firewall surface than the topology calls
        for. Default-deny aligns with the rest of the network policy
        (Caddy on :80 + :443 from caddy.nix is the canonical entry).
      */
      networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.flatten (
        lib.mapAttrsToList (_: cfg: lib.optional cfg.exposeOnTailnet cfg.port) (
          lib.filterAttrs (_: cfg: cfg.host == config.nori.inventory.currentHost) routes
        )
      );

      /*
        Auto-generated Gatus endpoints for routes that opt in via
        `monitor`. Manual entries in services/gatus/nixos.nix
        (blocky-dns, samba-smb) coexist via list concatenation.
      */
      services.gatus.settings.endpoints = lib.mkAfter (
        lib.mapAttrsToList (name: cfg: {
          inherit name;
          url = "${cfg.scheme}://${routeHost cfg}:${toString cfg.port}${cfg.monitor.path}";
          inherit (cfg.monitor) interval conditions;
          headers = cfg.monitor.headers;
          alerts = [
            {
              type = "ntfy";
              failure-threshold = cfg.monitor.failureThreshold;
              send-on-resolved = true;
            }
          ];
        }) (filterAttrs (_: cfg: cfg.monitor != null) routes)
      );

      /**
        OIDC plumbing for routes with `oidc` set. The Authelia client
        entry is assembled by services/authelia/nixos.nix reading
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
        /*
          Raw client secrets exist only on the host that runs each backend.
          Hosts importing the shared route registry receive no unrelated
          credential material.
        */
        (mapAttrs' (
          name: _:
          nameValuePair "oidc-${name}-client-secret" {
            mode = "0440";
            group = "keys";
          }
        ) localOidcRoutes)
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
          ) oidcRoutes
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
      ) localOidcRoutes;
    }
  );
}
