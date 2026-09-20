{ config, lib, ... }:

{
  /*
    Miniflux — minimal RSS / feed reader (Go binary + Postgres). All
    state in Postgres; no on-disk per-user files.

    === Bootstrap ===
      1. Follow secrets/README.md "OIDC client rotation" for `news`.
      2. Store MINIFLUX_ADMIN_PASSWORD through the Adelie SecretSpec profile.
      3. Run the deployment plan, then activate Adelie.
      4. https://news.home.phibkro.org → click "Continue with Authelia". OIDC
         auto-creates the matching miniflux account on first SSO via
         OAUTH2_USER_CREATION=1; first user in is the admin.
      5. The `admin` account from miniflux-admin-password is the
         master fallback (Authelia-down recovery). Keep it in a real
         password manager.

    === Postgres ownership ===
    `createDatabaseLocally = true` enables Adelie's local PostgreSQL instance
    and creates an isolated `miniflux` database and user. No cross-host
    database dependency exists.
  */

  services.miniflux = {
    enable = true;
    createDatabaseLocally = true;

    config = {
      /*
        Pi Caddy reverse-proxies `news.<nori.domain>` to this service on 8087.
        This is the next free route port between `home` and `metrics`.
      */
      LISTEN_ADDR = "0.0.0.0:8087";
      BASE_URL = "https://news.${config.nori.inventory.site.domain}";

      /*
        OIDC via Authelia. Non-secret OIDC vars live here; the secret
        itself is injected via the EnvironmentFile (sops template)
        below alongside the admin credentials.
      */
      OAUTH2_PROVIDER = "oidc";
      OAUTH2_CLIENT_ID = "news";
      OAUTH2_REDIRECT_URL = "https://news.${config.nori.inventory.site.domain}/oauth2/oidc/callback";
      OAUTH2_OIDC_DISCOVERY_ENDPOINT = "https://auth.${config.nori.inventory.site.domain}";
      /*
        Auto-create miniflux user on first SSO. With this off, the
        admin would have to pre-create every family member's account
        manually — the whole point of OIDC integration is to skip
        that. First SSO sign-in lands a new user; subsequent sign-ins
        match by `sub` claim.
      */
      OAUTH2_USER_CREATION = 1;
    };

    /*
      Single sops template carries both the admin bootstrap creds AND
      the OAUTH2 client secret. Miniflux's upstream module exposes
      exactly one `adminCredentialsFile` (→ EnvironmentFile slot), so
      collapsing both secrets into one file is simpler than fighting
      the module's single-file shape with mkForce. The lan-route
      abstraction also auto-generates a `oidc-news-env` template
      carrying just OAUTH2_CLIENT_SECRET; that template is harmless
      but unused — left orphaned rather than introducing a new
      `envAdditionalContent` knob across all services for one case.
    */
    adminCredentialsFile = config.sops.templates."miniflux-env".path;
  };

  users.groups.miniflux-secrets = { };

  sops.templates."oidc-news-env" = {
    group = lib.mkForce "miniflux-secrets";
    mode = lib.mkForce "0440";
  };

  sops.templates."miniflux-env" = {
    mode = "0440";
    group = "miniflux-secrets";
    content = ''
      ADMIN_USERNAME=admin
      ADMIN_PASSWORD=${config.sops.placeholder."miniflux-admin-password"}
      OAUTH2_CLIENT_SECRET=${config.sops.placeholder."oidc-news-client-secret"}
    '';
  };

  sops.secrets."miniflux-admin-password" = { };

  # DynamicUser cannot own a file during activation. A service-specific group
  # grants Miniflux access without exposing other services' credentials.
  systemd.services.miniflux.serviceConfig.SupplementaryGroups = [ "miniflux-secrets" ];

  nori.harden.miniflux = { };

  /*
    Pattern C1 — pg_dump to /var/backup/postgresql/, restic picks it
    up below. services.postgresqlBackup is idempotent; another
    service enabling it just appends to `databases`.
  */
  services.postgresqlBackup = {
    enable = true;
    databases = [ "miniflux" ];
    startAt = "*-*-* 03:30:00"; # before restic-backups-miniflux at 04:30
    pgdumpOptions = "--no-owner";
  };

  # Every Miniflux Restic run must refresh its logical dump first. The unit
  # dependency makes a stale pre-cutover dump an invalid backup execution.
  systemd.services."restic-backups-miniflux-onetouch" = {
    requires = [ "postgresqlBackup-miniflux.service" ];
    after = [ "postgresqlBackup-miniflux.service" ];
  };

  nori.backups.miniflux = {
    include = [ "/var/backup/postgresql/miniflux.sql.gz" ];
    timer = "*-*-* 04:30:00";
  };
}
