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
  };

  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = config.sops.secrets.authelia-jwt-secret.path;
      sessionSecretFile = config.sops.secrets.authelia-session-secret.path;
      storageEncryptionKeyFile = config.sops.secrets.authelia-storage-encryption-key.path;
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
    };
  };

  systemd.services.authelia-main.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
    BindReadOnlyPaths = [ ];
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 9091 ];

  # Exposed at https://auth.nori.lan via Caddy.
  nori.lanRoutes.auth = { port = 9091; };
}
