{
  config,
  pkgs,
  ...
}:

{
  # Navidrome — Subsonic-protocol music server. Family-facing playback;
  # browser UI at https://audio.nori.lan, Subsonic-API clients
  # (Symfonium, DSub, play:Sub, Substreamer, Sonixd) connect to the
  # same URL.
  #
  # Reads music from /mnt/media/downloads/music (Lidarr's auto-grabbed
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
      MusicFolder = "${config.nori.fs.downloads.path}/music";
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

  # Transcoding requires ffmpeg on PATH; upstream NixOS module doesn't
  # add it. Without this, EnableTranscodingConfig=true exposes the UI
  # but every transcode silently fails at runtime. Pattern: keep FLAC on
  # disk (archival), let Navidrome transcode to MP3/Opus per-client
  # (Subsonic clients negotiate max bitrate per network).
  systemd.services.navidrome.path = [ pkgs.ffmpeg ];
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
  nori.harden.navidrome.readOnlyBinds = [ config.nori.fs.downloads.path ];

  nori.lanRoutes.audio = {
    port = 4533;
    monitor = { };
    audience = "family";
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
    include = [
      "/var/lib/private/navidrome"
      "/var/backup/navidrome"
    ];
    prepareCommand = ''
      if [ -f /var/lib/navidrome/navidrome.db ]; then
        mkdir -p /var/backup/navidrome
        # VACUUM INTO + PRAGMA busy_timeout, NOT `.backup`. The sqlite3
        # CLI's `.backup` dot-command has a hard-coded retry loop of
        # ~2.5s and silently ignores busy_timeout — so the previous
        # `.timeout 30000` "fix" was a no-op; navidrome's 04:45 backup
        # kept failing with "database is locked" the instant a writer
        # held the lock. VACUUM INTO is a regular SQL statement, runs
        # on the main connection, and honors busy_timeout. Tmp +
        # atomic rename so a torn write never leaves a half-finished
        # target. Caught 2026-06-06; same pattern applies to
        # open-webui.nix + vaultwarden.nix.
        # Serialize concurrent prep — both `-onetouch` and `-ironwolf`
        # restic targets fire at the same minute and race on .tmp.
        # Loser sees winner's partial VACUUM INTO write and bombs with
        # "table goose_db_version already exists". flock makes them
        # take turns; second caller just re-dumps the now-fresh state.
        (
          ${pkgs.util-linux}/bin/flock -x 9
          rm -f /var/backup/navidrome/navidrome.db.tmp
          ${pkgs.sqlite}/bin/sqlite3 /var/lib/navidrome/navidrome.db \
            "PRAGMA busy_timeout = 30000;" \
            "VACUUM INTO '/var/backup/navidrome/navidrome.db.tmp';"
          mv /var/backup/navidrome/navidrome.db.tmp /var/backup/navidrome/navidrome.db
        ) 9>/var/backup/navidrome/.prep.lock
      fi
    '';
    timer = "*-*-* 04:45:00"; # stagger off vaultwarden (04:30) + open-webui (04:00)
  };
}
