{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkMerge [
  {
    nori.services.vaultwarden.tags = [
      "family-tier"
      "stateful"
    ];

    /**
      Route declaration is lifted outside the activation gate so any
      host importing this module sees vault.nori.lan in its lanRoutes
      registry — needed for the proxy host (pi/aurora/workstation,
      decided by host config) to know how to route + DNS even if the
      actual vaultwarden service runs elsewhere. `runsOn` tells the
      generators where the backend lives; lan-route resolves to
      127.0.0.1 on that host, tailnet IP on others.

      `/alive` returns "1" on healthy (Vaultwarden's health endpoint).
    */
    nori.lanRoutes.vault = {
      port = 8222;
      runsOn = "aurora";
      monitor = {
        path = "/alive";
      };
      audience = "family";
      oidc = {
        clientName = "Vaultwarden";
        redirectPath = "/identity/connect/oidc-signin";
        secretEnvName = "SSO_CLIENT_SECRET";
        /*
          `openid` (always implicit) + the three standard claims +
          offline_access for refresh tokens. The Authelia client must
          list `offline_access` for the request to be allowed; this
          matches `services.vaultwarden.config.SSO_SCOPES` above.
        */
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
  (lib.mkIf config.nori.services.vaultwarden.enabled {
    /*
      Vaultwarden — self-hosted Bitwarden-compatible password manager.
      Mainline 1.35.0+ (Dec 2024) ships native OIDC SSO; the Timshel
      fork is no longer required.

      === Bootstrap ===
        1. just generate-oidc-key vault   → outputs raw + PBKDF2 hash
        2. sops secrets/secrets.yaml → add as block-scalar:
             oidc-vault-client-secret: '<raw>'
             oidc-vault-client-secret-hash: '<paste-hash-from-just-oidc-key>'
        3. just rebuild
        4. Connect to https://vault.nori.lan
        5. Create master account (used as password-fallback if Authelia
           is ever down; SSO_ONLY = false leaves the door open).
        6. Sign out, click "Continue with Authelia" — should round-trip
           and auto-link to your account when emails match.

      === Migration from cloud Bitwarden (one-time) ===
        - cloud → Tools → Export Vault → "Bitwarden (encrypted json)"
        - vault.nori.lan → Tools → Import → Bitwarden JSON
        - verify all entries opened correctly
        - keep the cloud account dormant for ~30 days as recovery
          before deleting (Vaultwarden bugs late-discovered are
          irreversible without a fallback)
    */

    services.vaultwarden = {
      enable = true;
      dbBackend = "sqlite"; # default; explicit. Postgres adds infra without value at single-user.
      config = {
        /*
          Network — Caddy at vault.<nori.domain> reverse-proxies to
          the runsOn host. Bind 0.0.0.0 so the entry-plane Caddy can
          reach this backend over the tailnet when runsOn ≠ Caddy host.
          The appliance-scoped Caddy-reach rule (modules/infra/networking)
          opens 8222 on tailscale0 to the appliance host ONLY — NOT all
          peers, so a tailnet device can't curl 8222 and skip Authelia
          (this route is audience=family / OIDC). LAN stays closed.
        */
        DOMAIN = "https://vault.${config.nori.domain}";
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = 8222;

        /*
          SIGNUPS_ALLOWED is closed in steady state — single-user
          homelab. Existing accounts can still be unlocked via SSO
          (linked by email) or master password; the flag only gates
          the /identity/accounts/register endpoint that creates new
          accounts. To onboard a new user (family member, etc.):
            1. flip to `true` for one rebuild
            2. user registers a master account at vault.nori.lan
            3. ensure their Authelia user has the same email so
               SSO_SIGNUPS_MATCH_EMAIL links the SSO identity
            4. flip back to `false`
          SIGNUPS_VERIFY off because no SMTP server is configured.
        */
        SIGNUPS_ALLOWED = false;
        SIGNUPS_VERIFY = false;

        /*
          OIDC SSO via Authelia. SSO_ONLY left at default (false) so the
          master password remains a recovery path if Authelia is down —
          both services live on the same host, so a host failure that
          takes down Authelia would also take down Vaultwarden, but the
          asymmetric case (Authelia broken, Vaultwarden fine) is real.
        */
        SSO_ENABLED = true;
        SSO_AUTHORITY = "https://auth.${config.nori.domain}";
        SSO_CLIENT_ID = "vault";
        # SSO_CLIENT_SECRET injected via EnvironmentFile (sops template);
        # see systemd.services.vaultwarden.serviceConfig below.
        SSO_PKCE = true; # PKCE S256 — Authelia enforces it; default true, explicit for the record.
        /*
          `offline_access` is critical: without it Bitwarden's 5-min
          relock detector trips at every access-token expiry. With it,
          Vaultwarden refreshes silently and sessions stay live.
        */
        SSO_SCOPES = "profile email offline_access";
        SSO_SIGNUPS_MATCH_EMAIL = true;
      };
    };

    nori.harden.vaultwarden = { };

    /*
      SSO_CLIENT_SECRET comes from the sops template auto-generated
      by lan-route. Vaultwarden runs under a static `vaultwarden`
      user (not DynamicUser) so technically `SupplementaryGroups`
      could be skipped — but the upstream module owns the user, and
      the env file's mode is 0440 root:keys, so adding `keys`
      explicitly keeps the convention uniform across services.
    */
    systemd.services.vaultwarden.serviceConfig = {
      EnvironmentFile = config.sops.templates."oidc-vault-env".path;
      SupplementaryGroups = [ "keys" ];
    };

    /*
      Pattern C2 — VACUUM INTO snapshot before restic. Static
      `vaultwarden` user (not DynamicUser), so /var/lib/vaultwarden is
      a real directory. The `if` guards the bootstrap case where the
      DB doesn't exist yet.
    */
    nori.backups.vaultwarden = {
      include = [
        "/var/lib/vaultwarden"
        "/var/backup/vaultwarden"
      ];
      prepareCommand = ''
        if [ -f /var/lib/vaultwarden/db.sqlite3 ]; then
          mkdir -p /var/backup/vaultwarden
          # VACUUM INTO + PRAGMA busy_timeout — see the long-form # multi-line: ok
          # rationale in navidrome.nix. The sqlite3 CLI's `.backup`
          # ignores busy_timeout, so the previous `.timeout 30000` was
          # a no-op. Vaultwarden writes on every sync/login.
          # Serialize concurrent prep — onetouch + mp510 race fix.
          # See navidrome.nix for the long form.
          (
            ${pkgs.util-linux}/bin/flock -x 9
            rm -f /var/backup/vaultwarden/db.sqlite3.tmp
            ${pkgs.sqlite}/bin/sqlite3 /var/lib/vaultwarden/db.sqlite3 \
              "PRAGMA busy_timeout = 30000;" \
              "VACUUM INTO '/var/backup/vaultwarden/db.sqlite3.tmp';"
            mv /var/backup/vaultwarden/db.sqlite3.tmp /var/backup/vaultwarden/db.sqlite3
          ) 9>/var/backup/vaultwarden/.prep.lock
        fi
      '';
      timer = "*-*-* 04:30:00";
    };

  })
]
