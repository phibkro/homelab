{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Vaultwarden — self-hosted Bitwarden-compatible password manager.
  # Mainline Vaultwarden 1.35.0+ (Dec 2024) ships native OIDC SSO; the
  # Timshel fork is no longer required. This is the third validator for
  # the lan-route OIDC abstraction (after chat and the deferred
  # metrics).
  #
  # === Bootstrap ===
  #   1. just oidc-key vault   → outputs raw + PBKDF2 hash
  #   2. sops secrets/secrets.yaml → add as block-scalar:
  #        oidc-vault-client-secret: '<raw>'
  #        oidc-vault-client-secret-hash: '<paste-hash-from-just-oidc-key>'
  #   3. just rebuild
  #   4. Connect to https://vault.nori.lan
  #   5. Create master account (used as password-fallback if Authelia
  #      is ever down; SSO_ONLY = false leaves the door open).
  #   6. Sign out, click "Continue with Authelia" — should round-trip
  #      and auto-link to your account when emails match.
  #
  # === Migration from cloud Bitwarden (one-time) ===
  #   - cloud → Tools → Export Vault → "Bitwarden (encrypted json)"
  #   - vault.nori.lan → Tools → Import → Bitwarden JSON
  #   - verify all entries opened correctly
  #   - keep the cloud account dormant for ~30 days as recovery
  #     before deleting (Vaultwarden bugs late-discovered are
  #     irreversible without a fallback)
  #
  # === Backup ===
  # State at /var/lib/vaultwarden (SQLite). Backup is Pattern C2 in
  # backup/restic.nix's `vaultwarden` repo — `sqlite3 .backup` before
  # restic for a consistent dump. Same shape as open-webui.

  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite"; # default; explicit. Postgres adds infra without value at single-user.
    config = {
      # Network — Caddy at vault.nori.lan reverse-proxies to localhost.
      # The upstream default ROCKET_ADDRESS is `::1` (IPv6 localhost);
      # we switch to IPv4 so Caddy's reverse_proxy hits the same
      # family the lan-route abstraction expects (host = "127.0.0.1"
      # by default).
      DOMAIN = "https://vault.nori.lan";
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;

      # SIGNUPS_ALLOWED is closed in steady state — single-user
      # homelab. Existing accounts can still be unlocked via SSO
      # (linked by email) or master password; the flag only gates
      # the /identity/accounts/register endpoint that creates new
      # accounts. To onboard a new user (family member, etc.):
      #   1. flip to `true` for one rebuild
      #   2. user registers a master account at vault.nori.lan
      #   3. ensure their Authelia user has the same email so
      #      SSO_SIGNUPS_MATCH_EMAIL links the SSO identity
      #   4. flip back to `false`
      # SIGNUPS_VERIFY off because no SMTP server is configured.
      SIGNUPS_ALLOWED = false;
      SIGNUPS_VERIFY = false;

      # OIDC SSO via Authelia. SSO_ONLY left at default (false) so the
      # master password remains a recovery path if Authelia is down —
      # both services live on the same host, so a host failure that
      # takes down Authelia would also take down Vaultwarden, but the
      # asymmetric case (Authelia broken, Vaultwarden fine) is real.
      SSO_ENABLED = true;
      SSO_AUTHORITY = "https://auth.nori.lan";
      SSO_CLIENT_ID = "vault";
      # SSO_CLIENT_SECRET injected via EnvironmentFile (sops template);
      # see systemd.services.vaultwarden.serviceConfig below.
      SSO_PKCE = true; # PKCE S256 — Authelia enforces it; default true, explicit for the record.
      # `offline_access` is critical: without it Bitwarden's 5-min
      # relock detector trips at every access-token expiry. With it,
      # Vaultwarden refreshes silently and sessions stay live.
      SSO_SCOPES = "profile email offline_access";
      SSO_SIGNUPS_MATCH_EMAIL = true;
    };
  };

  nori.harden.vaultwarden = { };

  # SSO_CLIENT_SECRET comes from the sops template auto-generated
  # by lan-route. Vaultwarden runs under a static `vaultwarden`
  # user (not DynamicUser) so technically `SupplementaryGroups`
  # could be skipped — but the upstream module owns the user, and
  # the env file's mode is 0440 root:keys, so adding `keys`
  # explicitly keeps the convention uniform across services.
  systemd.services.vaultwarden.serviceConfig = {
    EnvironmentFile = config.sops.templates."oidc-vault-env".path;
    SupplementaryGroups = [ "keys" ];
  };

  # Pattern C2 backup — sqlite3 .backup before restic. Vaultwarden
  # uses a static `vaultwarden` user (not DynamicUser), so
  # /var/lib/vaultwarden is a real directory, not a symlink. The
  # prepareCommand handles the bootstrap case where the DB doesn't
  # exist yet.
  nori.backups.vaultwarden = {
    paths = [
      "/var/lib/vaultwarden"
      "/var/backup/vaultwarden"
    ];
    prepareCommand = ''
      if [ -f /var/lib/vaultwarden/db.sqlite3 ]; then
        mkdir -p /var/backup/vaultwarden
        ${pkgs.sqlite}/bin/sqlite3 /var/lib/vaultwarden/db.sqlite3 \
          ".backup '/var/backup/vaultwarden/db.sqlite3'"
      fi
    '';
    timer = "*-*-* 04:30:00";
  };

  # Exposed at https://vault.nori.lan via Caddy. /alive returns "1"
  # when the service is healthy (Vaultwarden's own health endpoint).
  # OIDC client + sops secrets + env-file template auto-generated by
  # the lan-route abstraction; see modules/effects/lan-route.nix.
  nori.lanRoutes.vault = {
    port = 8222;
    monitor = {
      path = "/alive";
    };
    audience = "family";
    oidc = {
      clientName = "Vaultwarden";
      redirectPath = "/identity/connect/oidc-signin";
      secretEnvName = "SSO_CLIENT_SECRET";
      # `openid` (always implicit) + the three standard claims +
      # offline_access for refresh tokens. The Authelia client must
      # list `offline_access` for the request to be allowed; this
      # matches `services.vaultwarden.config.SSO_SCOPES` above.
      scopes = [
        "openid"
        "profile"
        "email"
        "groups"
        "offline_access"
      ];
    };
  };
}
