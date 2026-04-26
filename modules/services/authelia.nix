{ config, lib, pkgs, ... }:

{
  # Authelia — single sign-on portal. Per DESIGN's "Open items":
  # Authelia chosen over self-hosted SSO alternatives (Authentik,
  # Keycloak) for declarative-first design, lightweight footprint
  # (~50MB RAM), file-based config, and good NixOS module support.
  #
  # PHASE A (this module): Authelia service running, file-based user
  # database with one admin user, password login works at port 9091
  # over the tailnet. No OIDC client integration yet — just the
  # foundation that subsequent services delegate to.
  #
  # PHASE B (next): per-service OIDC client setup. Each service
  # configures Authelia as its OIDC issuer; users sign in once via
  # Authelia, services trust the resulting tokens. One-click SSO.
  #
  # Connect to: http://nori-station.saola-matrix.ts.net:9091
  # Initial login: user = nori, password = whatever you hashed during
  # secrets bootstrap.
  #
  # Sops secrets needed (Phase A):
  #   authelia-jwt-secret              random hex (>=32 bytes)
  #   authelia-session-secret          random hex (>=32 bytes)
  #   authelia-storage-encryption-key  random hex (>=32 bytes)
  #   authelia-users-database          YAML block with users/groups
  #
  # See module comment for the secret-generation command sequence.

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
        path = config.sops.secrets.authelia-users-database.path;
        password.algorithm = "argon2";
      };

      session = {
        # Authelia served via Caddy reverse proxy at https://auth.nori.lan
        # — Caddy terminates TLS via its internal CA, proxies to
        # Authelia's local HTTP on port 9091. Cookie domain matches
        # the parent name so sessions can carry across other
        # *.nori.lan subdomains for SSO scope (Phase B).
        cookies = [{
          domain = "nori.lan";
          authelia_url = "https://auth.nori.lan";
          name = "authelia_session";
        }];
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

      # OIDC clients — manually declared per service for now.
      # Auto-generation deferred (would need sops template + Authelia
      # expand-env filter + per-service env-file plumbing). Add a new
      # client by:
      #   1. Generate raw secret + PBKDF2 hash via:
      #        authelia crypto hash generate pbkdf2 --variant sha512 \
      #          --iterations 310000 --password '<raw>'
      #   2. Add raw to sops as oidc-<name>-client-secret
      #   3. Append the entry below with the hash inline
      #   4. Wire the consuming service (per-service env vars)
      identity_providers.oidc.clients = [
        {
          client_id = "chat";
          client_name = "Open WebUI";
          client_secret = "$pbkdf2-sha512$310000$ThTc2qRfMD0r/GkaCjySYA$fWbF1FfUDlwK1IgoSe9XBeXrJjocYfC0VJis24qHZ54pweEKIuMrd6QUDuASRPpSBoocwJRM8OKuKDKLRX29Yg";
          public = false;
          authorization_policy = "one_factor";
          redirect_uris = [
            "https://chat.nori.lan/oauth/oidc/callback"
          ];
          scopes = [ "openid" "profile" "email" "groups" ];
        }
        {
          client_id = "metrics";
          client_name = "Beszel";
          client_secret = "$pbkdf2-sha512$310000$0gc7ZQ3BvBSY9j9osv4GDw$V0XEUOAvm6u0Ox5Uro7Yy5m1srM3nqLkI4BrJU6J0t8L53C01feT6bgiNokwuC8WNpp6MKu30MBzhhe.ZCjkdg";
          public = false;
          authorization_policy = "one_factor";
          # Beszel inherits PocketBase's OAuth2 flow — callback path
          # is /api/oauth2-redirect (standard PocketBase pattern).
          redirect_uris = [
            "https://metrics.nori.lan/api/oauth2-redirect"
          ];
          scopes = [ "openid" "profile" "email" "groups" ];
        }
      ];
    };
  };

  systemd.services.authelia-main.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
    BindReadOnlyPaths = [ ];
  };

  # Exposed at https://auth.nori.lan via Caddy. Auto-monitored.
  nori.lanRoutes.auth = {
    port = 9091;
    monitor = { };
  };
}
