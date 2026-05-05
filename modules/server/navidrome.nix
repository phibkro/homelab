{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Navidrome — Subsonic-protocol music server. Family-facing playback;
  # browser UI at https://audio.nori.lan, Subsonic-API clients
  # (Symfonium, DSub, play:Sub, Substreamer, Sonixd) connect to the
  # same URL.
  #
  # Reads music from /mnt/media/streaming/music (Lidarr's auto-grabbed
  # library) read-only — Navidrome scans + indexes into its own SQLite
  # but never writes to the source tree. State (user accounts,
  # playlists, scrobble history, transcoding cache) at
  # /var/lib/navidrome (DynamicUser symlink → /var/lib/private/navidrome;
  # backup paths target the private dir per the symlink-trap assertion).
  #
  # ── Naming ──────────────────────────────────────────────────────
  # The `music` lanRoute is taken by Lidarr (acquire-tier). Navidrome
  # uses `audio` to avoid the conflict. Rename one if the asymmetry
  # ever bothers you — single-line edit, DNS + Caddy + Glance auto-
  # update.
  #
  # ── First-run setup ────────────────────────────────────────────
  #   1. just oidc-key audio
  #   2. sops secrets/secrets.yaml — paste raw + hash:
  #        oidc-audio-client-secret: '<raw>'
  #        oidc-audio-client-secret-hash: '<hash>'
  #   3. just rebuild
  #   4. https://audio.nori.lan
  #   5. First-launch wizard — create master admin account (this is
  #      the recovery path if Authelia is ever down). Use a real
  #      password manager entry.
  #   6. Settings → Users → enable "Login with Authelia" (the OIDC
  #      env vars below take effect on service start; web UI exposes
  #      the SSO button automatically once ND_AUTH_OIDC_ENABLED=true)
  #   7. Family members log in with "Sign in with Authelia" — auto-
  #      creates a Navidrome user linked to their Authelia identity
  #      via the `preferred_username` claim.
  #
  # ── Subsonic API clients ───────────────────────────────────────
  # OIDC is web-only. Subsonic clients (mobile / desktop apps) use
  # the per-user "Subsonic API password" set inside Navidrome:
  #   Settings → Personal → Generate Subsonic API token
  # Connection details for clients:
  #   Server URL:  https://audio.nori.lan
  #   Username:    <navidrome username>
  #   Password:    <subsonic-api token, NOT the web password>
  #
  # ── OIDC env-var notes ──────────────────────────────────────────
  # Navidrome's TOML config keys map to env vars as ND_<SECTION>_<KEY>
  # with no separators inside multi-word keys (DiscoveryURL →
  # DISCOVERYURL, ClientID → CLIENTID). Env-var names verified against
  # Navidrome 0.55+; if Navidrome rejects with "unknown config key",
  # check the running version's docs and adjust here.

  services.navidrome = {
    enable = true;
    openFirewall = false;
    settings = {
      Address = "127.0.0.1";
      Port = 4533;
      MusicFolder = "${config.nori.fs.streaming.path}/music";
      EnableTranscodingConfig = true;
    };
  };

  # OIDC env vars + the env-file-injected client secret. The lan-route
  # abstraction generates the env file at /run/secrets/rendered/oidc-audio-env
  # with key `ND_AUTH_OIDC_CLIENTSECRET=<raw>` (per `secretEnvName`
  # below). Non-secret config goes in `environment` directly.
  systemd.services.navidrome.serviceConfig = {
    EnvironmentFile = config.sops.templates."oidc-audio-env".path;
    SupplementaryGroups = [ "keys" ];
  };
  systemd.services.navidrome.environment = {
    ND_AUTH_OIDC_ENABLED = "true";
    ND_AUTH_OIDC_PROVIDERNAME = "Authelia";
    ND_AUTH_OIDC_DISCOVERYURL = "https://auth.nori.lan/.well-known/openid-configuration";
    ND_AUTH_OIDC_CLIENTID = "audio";
    # ND_AUTH_OIDC_CLIENTSECRET injected via EnvironmentFile above.
    ND_AUTH_OIDC_REDIRECTURL = "https://audio.nori.lan/auth/callback";
    ND_AUTH_OIDC_USERNAMECLAIM = "preferred_username";
  };

  # Default-deny FS hardening with read-only access to Lidarr's music
  # library. Navidrome's own state at /var/lib/private/navidrome is
  # handled by the upstream module's StateDirectory.
  nori.harden.navidrome.readOnlyBinds = [ config.nori.fs.streaming.path ];

  nori.lanRoutes.audio = {
    port = 4533;
    monitor = { };
    oidc = {
      clientName = "Navidrome";
      redirectPath = "/auth/callback";
      secretEnvName = "ND_AUTH_OIDC_CLIENTSECRET";
    };
    dashboard = {
      title = "Navidrome";
      icon = "sh:navidrome";
      group = "Consume";
      description = "Subsonic-protocol music streaming";
    };
  };

  # Pattern C2 — sqlite3 .backup before restic. DynamicUser's symlink
  # at /var/lib/navidrome → /var/lib/private/navidrome means restic
  # paths target the private dir directly (the symlink-trap assertion
  # in modules/effects/backup.nix catches the wrong shape at eval).
  # The prepareCommand can use either path — bash file ops follow
  # symlinks.
  nori.backups.navidrome = {
    paths = [
      "/var/lib/private/navidrome"
      "/var/backup/navidrome"
    ];
    prepareCommand = ''
      if [ -f /var/lib/navidrome/navidrome.db ]; then
        mkdir -p /var/backup/navidrome
        ${pkgs.sqlite}/bin/sqlite3 /var/lib/navidrome/navidrome.db \
          ".backup '/var/backup/navidrome/navidrome.db'"
      fi
    '';
    timer = "*-*-* 04:45:00"; # stagger off vaultwarden (04:30) + open-webui (04:00)
  };
}
