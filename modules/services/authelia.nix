{
  config,
  lib,
  ...
}:

let
  # OIDC clients assembled here (not at call sites) because NixOS
  # module merging on freeform-typed lists conflicts rather than
  # concatenates — centralized assembly avoids mkMerge ceremony per
  # client. Schema lives in modules/infra/networking/default.nix.
  #
  # `client_secret` uses the template config-filter (enabled below)
  # to read the PBKDF2 hash from sops at startup — hash never lands
  # in committed Nix. See .claude/skills/gotcha-authelia-template-filter/.
  generatedClients = lib.mapAttrsToList (name: route: {
    client_id = name;
    client_name = route.oidc.clientName;
    client_secret = ''{{ secret "/run/secrets/oidc-${name}-client-secret-hash" }}'';
    public = false;
    authorization_policy = route.oidc.authorizationPolicy;
    redirect_uris = [ "https://${name}.${config.nori.domain}${route.oidc.redirectPath}" ];
    inherit (route.oidc) scopes;

    # Standard authorization-code flow. `refresh_token` grant is
    # added iff the client requests `offline_access` — Authelia 4.39
    # rejects asymmetric configs in both directions:
    #   offline_access scope without refresh_token grant → no
    #     refresh_token issued (trips Bitwarden's relock-on-expiry).
    #   refresh_token grant without offline_access scope → warning
    #     "should only have refresh_token if also configured with
    #     offline_access scope" (becomes an error in future versions).
    # Hardcoded shape otherwise — every client we run is a
    # confidential web-app on auth-code flow; add a per-client
    # override field if we ever onboard a public/SPA client.
    response_types = [ "code" ];
    grant_types = [
      "authorization_code"
    ]
    ++ lib.optional (lib.elem "offline_access" route.oidc.scopes) "refresh_token";
  }) (lib.filterAttrs (_: cfg: cfg.oidc != null) config.nori.lanRoutes);
in
lib.mkMerge [
  {
    nori.services.authelia.tags = [
      "network-appliance"
      "stateful"
    ];

    # The SSO portal itself — `public` audience by definition (anyone
    # with tailnet trust hits this to get a session for the family-tier
    # services that consume OIDC).
    nori.lanRoutes.auth = {
      port = 9091;
      runsOn = "pi";
      monitor = { };
      audience = "public";
      dashboard = {
        title = "Authelia";
        icon = "sh:authelia";
        group = "Admin";
        description = "OIDC SSO issuer";
      };
    };
  }
  (lib.mkIf config.nori.services.authelia.enabled {
    # Authelia — SSO portal. Chosen over Authentik / Keycloak for
    # declarative-first design + ~50MB footprint + good NixOS module.
    #
    # Connect: https://auth.nori.lan — user = nori, password from
    # secrets bootstrap. Add an OIDC client by declaring
    # `nori.lanRoutes.<name>.oidc = { ... }` in the consuming module
    # (see open-webui.nix / beszel.nix). OIDC client secrets are
    # auto-declared by modules/infra/networking/default.nix.

    sops.secrets = {
      # All base secrets carry `restartUnits` so a sops edit + rebuild
      # is sufficient — the live process picks up the new value without
      # a manual `systemctl restart authelia-main`. Without this the
      # in-memory copy survives the rebuild (caching users from the
      # file backend; signing tokens with the previous jwt/session/
      # storage/oidc-hmac/issuer-key) and silently runs on the stale
      # secret until the next reboot or manual restart.
      authelia-jwt-secret = {
        mode = "0400";
        owner = "authelia-main";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-session-secret = {
        mode = "0400";
        owner = "authelia-main";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-storage-encryption-key = {
        mode = "0400";
        owner = "authelia-main";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-users-database = {
        mode = "0400";
        owner = "authelia-main";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-oidc-hmac-secret = {
        mode = "0400";
        owner = "authelia-main";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-oidc-issuer-private-key = {
        mode = "0400";
        owner = "authelia-main";
        restartUnits = [ "authelia-main.service" ];
      };
    };

    services.authelia.instances.main = {
      enable = true;

      secrets = {
        jwtSecretFile = config.sops.secrets.authelia-jwt-secret.path;
        sessionSecretFile = config.sops.secrets.authelia-session-secret.path;
        storageEncryptionKeyFile = config.sops.secrets.authelia-storage-encryption-key.path;
        oidcHmacSecretFile = config.sops.secrets.authelia-oidc-hmac-secret.path;
        oidcIssuerPrivateKeyFile = config.sops.secrets.authelia-oidc-issuer-private-key.path;
      };

      settings = {
        server.address = "tcp://0.0.0.0:9091/";
        log.level = "info";
        theme = "dark";

        authentication_backend.file = {
          inherit (config.sops.secrets.authelia-users-database) path;
          password.algorithm = "argon2";
        };

        session = {
          # Authelia served via Caddy reverse proxy at
          # https://auth.<nori.domain> — Caddy terminates TLS,
          # proxies to Authelia's local HTTP on port 9091. Cookie
          # domain matches the parent name so sessions can carry
          # across the other *.<nori.domain> subdomains for SSO scope.
          cookies = [
            {
              domain = config.nori.domain;
              authelia_url = "https://auth.${config.nori.domain}";
              name = "authelia_session";
            }
          ];
        };

        storage.local.path = "/var/lib/authelia-main/db.sqlite3";

        # Filesystem notifier — password reset emails get written to a
        # local file instead of going via SMTP. For single-user homelab,
        # SMTP is overkill; just `cat /var/lib/authelia-main/notification.txt`
        # if you ever need a reset link.
        notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";

        access_control = {
          default_policy = "one_factor";
          rules = [ ];
        };

        # OIDC clients are assembled from `nori.lanRoutes.<n>.oidc`
        # declarations across the per-service modules. The hash
        # (`client_secret`) is committed inline at the lan-route call
        # site; PBKDF2 is one-way so the raw secret can't be recovered
        # from it. The raw secret lives sops-encrypted at
        # `/run/secrets/oidc-<name>-client-secret`. See
        # .claude/skills/add-oidc-client/ for the bootstrap workflow.
        identity_providers.oidc.clients = generatedClients;
      };
    };

    # Template config-filter — read PBKDF2 hashes from sops at startup
    # for `generatedClients` above. See
    # .claude/skills/gotcha-authelia-template-filter/ for why `_FILE`
    # doesn't work on list-typed sections.
    systemd.services.authelia-main.environment = {
      X_AUTHELIA_CONFIG_FILTERS = "template";
    };

    nori.harden.authelia-main = { };

    # Pattern A — Authelia state: sqlite session store, OIDC issuer
    # state, rate-limiting counters. Without it, every OIDC client
    # has to be re-bootstrapped on a restore (clients-list reseeds
    # via this module on rebuild, but session continuity + OIDC
    # consent state needs the on-disk db). Static `authelia-main` user.
    nori.backups.authelia.include = [ "/var/lib/authelia-main" ];
  })
]
