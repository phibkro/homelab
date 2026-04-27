{
  config,
  lib,
  pkgs,
  ...
}:

let
  # OIDC clients are generated from `config.nori.lanRoutes.<n>.oidc`
  # — see modules/lib/lan-route.nix for the schema. This module is
  # the single owner of the Authelia clients list because NixOS
  # module merging on freeform-typed lists conflicts rather than
  # concatenates; centralized assembly avoids `lib.mkMerge` ceremony
  # at every call site.
  #
  # `client_secret` uses Authelia's template config-filter (enabled
  # below via X_AUTHELIA_CONFIG_FILTERS=template) to read the PBKDF2
  # hash from a sops-decrypted file at startup. The hash never lands
  # in committed Nix — only in sops. The filter pre-processes the
  # YAML config as text before YAML parsing, substituting
  # `{{ secret "/path" }}` with the file contents.
  generatedClients = lib.mapAttrsToList (name: route: {
    client_id = name;
    client_name = route.oidc.clientName;
    client_secret = ''{{ secret "/run/secrets/oidc-${name}-client-secret-hash" }}'';
    public = false;
    authorization_policy = route.oidc.authorizationPolicy;
    redirect_uris = [ "https://${name}.nori.lan${route.oidc.redirectPath}" ];
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
{
  # Authelia — single sign-on portal. Per DESIGN's "Open items":
  # Authelia chosen over self-hosted SSO alternatives (Authentik,
  # Keycloak) for declarative-first design, lightweight footprint
  # (~50MB RAM), file-based config, and good NixOS module support.
  #
  # PHASE A (landed): Authelia service running, file-based user
  # database with one admin user, password login works at port 9091.
  #
  # PHASE B (in progress): per-service OIDC client setup, generated
  # from the lan-route abstraction. Add a client by declaring
  # `nori.lanRoutes.<name>.oidc = { ... }` in the consuming service
  # module — see open-webui.nix and beszel.nix for examples.
  #
  # Connect to: https://auth.nori.lan
  # Initial login: user = nori, password = whatever you hashed during
  # secrets bootstrap.
  #
  # Sops secrets needed (Phase A):
  #   authelia-jwt-secret              random hex (>=32 bytes)
  #   authelia-session-secret          random hex (>=32 bytes)
  #   authelia-storage-encryption-key  random hex (>=32 bytes)
  #   authelia-users-database          YAML block with users/groups
  #
  # OIDC secrets (Phase B) live at `oidc-<name>-client-secret`,
  # auto-declared by modules/lib/lan-route.nix when `oidc` is set on
  # a route.

  sops.secrets = {
    authelia-jwt-secret = {
      mode = "0400";
      owner = "authelia-main";
    };
    authelia-session-secret = {
      mode = "0400";
      owner = "authelia-main";
    };
    authelia-storage-encryption-key = {
      mode = "0400";
      owner = "authelia-main";
    };
    authelia-users-database = {
      mode = "0400";
      owner = "authelia-main";
      # Authelia loads the file-based auth backend at startup and
      # caches users in memory; without an explicit restart the
      # service keeps the old user list after a sops update. sops-nix
      # restartUnits triggers the unit restart on content change so
      # `just rebuild` after editing this secret is sufficient — no
      # manual `systemctl restart authelia-main` step needed.
      restartUnits = [ "authelia-main.service" ];
    };
    # OIDC: required when identity_providers.oidc is enabled.
    # hmac-secret: HMAC for OIDC tokens (random hex)
    # issuer-private-key: RSA-2048 PEM, used to sign JWT id-tokens
    authelia-oidc-hmac-secret = {
      mode = "0400";
      owner = "authelia-main";
    };
    authelia-oidc-issuer-private-key = {
      mode = "0400";
      owner = "authelia-main";
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
        # Authelia served via Caddy reverse proxy at https://auth.nori.lan
        # — Caddy terminates TLS via its internal CA, proxies to
        # Authelia's local HTTP on port 9091. Cookie domain matches
        # the parent name so sessions can carry across other
        # *.nori.lan subdomains for SSO scope (Phase B).
        cookies = [
          {
            domain = "nori.lan";
            authelia_url = "https://auth.nori.lan";
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
      # docs/CONVENTIONS.md "Authelia OIDC pattern" for the bootstrap
      # workflow.
      identity_providers.oidc.clients = generatedClients;
    };
  };

  # Enable the template config-filter so per-OIDC-client `client_secret`
  # values rendered by `generatedClients` (above) can read their hash
  # from `/run/secrets/oidc-<n>-client-secret-hash` at Authelia startup.
  # The filter runs before YAML parsing and supports list entries,
  # which the legacy `_FILE`/`expand-env` paths do not.
  systemd.services.authelia-main.environment = {
    X_AUTHELIA_CONFIG_FILTERS = "template";
  };

  systemd.services.authelia-main.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
  };

  # Exposed at https://auth.nori.lan via Caddy. Auto-monitored.
  nori.lanRoutes.auth = {
    port = 9091;
    monitor = { };
  };

  # Pattern A — Authelia state: sqlite session store, OIDC issuer
  # state, rate-limiting counters. Without it, every OIDC client
  # has to be re-bootstrapped on a restore (clients-list reseeds
  # via this module on rebuild, but session continuity + OIDC
  # consent state needs the on-disk db). Static `authelia-main` user.
  nori.backups.authelia.paths = [ "/var/lib/authelia-main" ];
}
