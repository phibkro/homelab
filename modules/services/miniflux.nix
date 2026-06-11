{
  config,
  lib,
  ...
}:

lib.mkMerge [
  {
    nori.services.miniflux.tags = [
      "family-tier"
      "stateful"
    ];

    # `/healthcheck` returns 200 on a healthy daemon. The lan-route-
    # generated `oidc-news-env` template is unused (env file in use is
    # the combined `miniflux-env` above) — see `adminCredentialsFile`.
    nori.lanRoutes.news = {
      port = 8087;
      runsOn = "aurora";
      monitor = {
        path = "/healthcheck";
      };
      audience = "family";
      oidc = {
        clientName = "Miniflux";
        redirectPath = "/oauth2/oidc/callback";
        secretEnvName = "OAUTH2_CLIENT_SECRET";
      };
    };
  }
  (lib.mkIf config.nori.services.miniflux.enabled {
    # Miniflux — minimal RSS / feed reader (Go binary + Postgres). All
    # state in Postgres; no on-disk per-user files.
    #
    # === Bootstrap ===
    #   1. just generate-oidc-key news       → raw + PBKDF2 hash
    #   2. sops secrets/secrets.yaml — paste three secrets:
    #        oidc-news-client-secret:      '<raw from just generate-oidc-key>'
    #        oidc-news-client-secret-hash: '<hash from just generate-oidc-key>'
    #        miniflux-admin-password:      '<10+ chars; first-login fallback>'
    #   3. just rebuild
    #   4. https://news.nori.lan → click "Continue with Authelia". OIDC
    #      auto-creates the matching miniflux account on first SSO via
    #      OAUTH2_USER_CREATION=1; first user in is the admin.
    #   5. The `admin` account from miniflux-admin-password is the
    #      master fallback (Authelia-down recovery). Keep it in a real
    #      password manager.
    #
    # === Postgres sharing ===
    # `createDatabaseLocally = true` joins the shared
    # `services.postgresql` instance (already on via
    # services.immich.database.enable). immich + miniflux live
    # side-by-side with separate users — standard nixpkgs idiom.

    services.miniflux = {
      enable = true;
      createDatabaseLocally = true;

      config = {
        # Caddy at news.<nori.domain> reverse-proxies to localhost:8087.
        # 8087 is the next free port in the lanRoutes table (between
        # 8086 `home` and 8090 `metrics`).
        LISTEN_ADDR = "0.0.0.0:8087";
        BASE_URL = "https://news.${config.nori.domain}";

        # OIDC via Authelia. Non-secret OIDC vars live here; the secret
        # itself is injected via the EnvironmentFile (sops template)
        # below alongside the admin credentials.
        OAUTH2_PROVIDER = "oidc";
        OAUTH2_CLIENT_ID = "news";
        OAUTH2_REDIRECT_URL = "https://news.${config.nori.domain}/oauth2/oidc/callback";
        OAUTH2_OIDC_DISCOVERY_ENDPOINT = "https://auth.${config.nori.domain}";
        # Auto-create miniflux user on first SSO. With this off, the
        # admin would have to pre-create every family member's account
        # manually — the whole point of OIDC integration is to skip
        # that. First SSO sign-in lands a new user; subsequent sign-ins
        # match by `sub` claim.
        OAUTH2_USER_CREATION = 1;
      };

      # Single sops template carries both the admin bootstrap creds AND
      # the OAUTH2 client secret. Miniflux's upstream module exposes
      # exactly one `adminCredentialsFile` (→ EnvironmentFile slot), so
      # collapsing both secrets into one file is simpler than fighting
      # the module's single-file shape with mkForce. The lan-route
      # abstraction also auto-generates a `oidc-news-env` template
      # carrying just OAUTH2_CLIENT_SECRET; that template is harmless
      # but unused — left orphaned rather than introducing a new
      # `envAdditionalContent` knob across all services for one case.
      adminCredentialsFile = config.sops.templates."miniflux-env".path;
    };

    sops.templates."miniflux-env" = {
      mode = "0440";
      group = "keys";
      content = ''
        ADMIN_USERNAME=admin
        ADMIN_PASSWORD=${config.sops.placeholder."miniflux-admin-password"}
        OAUTH2_CLIENT_SECRET=${config.sops.placeholder."oidc-news-client-secret"}
      '';
    };

    sops.secrets."miniflux-admin-password" = { };

    # DynamicUser=true upstream → the unit can't read /run/secrets/*
    # without an extra group. `keys` is the sops-nix convention for
    # the secret-file owner; SupplementaryGroups grants read.
    systemd.services.miniflux.serviceConfig.SupplementaryGroups = [ "keys" ];

    nori.harden.miniflux = { };

    # Pattern C1 — pg_dump to /var/backup/postgresql/, restic picks it
    # up below. services.postgresqlBackup is idempotent; another
    # service enabling it just appends to `databases`.
    services.postgresqlBackup = {
      enable = true;
      databases = [ "miniflux" ];
      startAt = "*-*-* 03:30:00"; # before restic-backups-miniflux at 04:30
      pgdumpOptions = "--no-owner";
    };

    nori.backups.miniflux = {
      include = [ "/var/backup/postgresql/miniflux.sql.gz" ];
      timer = "*-*-* 04:30:00";
    };
  })
]
