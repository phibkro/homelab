{
  config,
  pkgs,
  ...
}:

let
  musicDataset = config.nori.inventory.datasets.music;
  musicPath = "${config.nori.fs.library.path}/${musicDataset.storage.relativePath}";
in
{
  /*
    Navidrome — Subsonic-protocol music server. Family-facing playback;
    browser UI at https://audio.home.phibkro.org, Subsonic-API clients
    (Symfonium, DSub, play:Sub, Substreamer, Sonixd) connect to the
    same URL.

    Reads music from `${nori.fs.library.path}/music` read-only —
    Navidrome scans + indexes into its own SQLite but never writes
    to the source tree. Curated tier (irreplaceable); Lidarr writes
    acquisitions to library/music alongside calibre's books + komga's
    comics. State (user accounts, playlists, scrobble history,
    transcoding cache) at /var/lib/navidrome (DynamicUser symlink →
    /var/lib/private/navidrome; backup paths target the private dir
    per the symlink-trap assertion).

    `music` is taken by Lidarr (acquire-tier); Navidrome uses `audio`.

    ── First-run setup ────────────────────────────────────────────
      1. Visit https://audio.home.phibkro.org.
      2. First-launch wizard — create the master admin account and store
         it in the password manager.
      3. Create one non-admin Navidrome user per family member. Native
         credentials are intentional: the OpenSubsonic protocol embeds
         its own authentication parameters and most clients cannot pass
         an Authelia browser session or generic OIDC flow.

    ── Subsonic API clients ───────────────────────────────────────
    Subsonic clients (mobile / desktop / PWA) use each family member's
    native Navidrome credential or per-user API password:
      Settings → Personal → Generate Subsonic API token (when supported)
    Connection details for clients:
      Server URL:  https://audio.home.phibkro.org
      Username:    <navidrome username>
      Password:    <native password or generated API password>
  */

  services.navidrome = {
    enable = true;
    openFirewall = false;
    settings = {
      Address = "0.0.0.0";
      Port = 4533;
      MusicFolder = musicPath;
      EnableTranscodingConfig = true;
      # Public reachability is account-gated. Disable unauthenticated
      # share URLs so every listener remains attributable to a user.
      EnableSharing = false;
    };
  };

  /*
    Transcoding requires ffmpeg on PATH; upstream NixOS module doesn't
    add it. Without this, EnableTranscodingConfig=true exposes the UI
    but every transcode silently fails at runtime. Pattern: keep FLAC on
    disk (archival), let Navidrome transcode to MP3/Opus per-client
    (Subsonic clients negotiate max bitrate per network).
  */
  systemd.services.navidrome.path = [ pkgs.ffmpeg ];

  /*
    Read-only access to the music tier; navidrome's own state at
    /var/lib/private/navidrome rides upstream's StateDirectory.
  */
  nori.harden.navidrome.readOnlyBinds = [ musicPath ];

  /*
    Pattern C2 — sqlite3 .backup before restic. DynamicUser's symlink
    at /var/lib/navidrome → /var/lib/private/navidrome means restic
    paths target the private dir directly (the symlink-trap assertion
    in modules/infra/backup/default.nix catches the wrong shape at eval).
    The prepareCommand can use either path — bash file ops follow
    symlinks.
  */
  nori.backups.navidrome = {
    include = [
      "/var/lib/private/navidrome"
      "/var/backup/navidrome"
    ];
    prepareCommand = ''
      if [ -f /var/lib/navidrome/navidrome.db ]; then
        mkdir -p /var/backup/navidrome
        # VACUUM INTO + PRAGMA busy_timeout, NOT `.backup`. The sqlite3 # multi-line: ok
        # CLI's `.backup` dot-command has a hard-coded retry loop of
        # ~2.5s and silently ignores busy_timeout — so the previous
        # `.timeout 30000` "fix" was a no-op; navidrome's 04:45 backup
        # kept failing with "database is locked" the instant a writer
        # held the lock. VACUUM INTO is a regular SQL statement, runs
        # on the main connection, and honors busy_timeout. Tmp +
        # atomic rename so a torn write never leaves a half-finished
        # target. Caught 2026-06-06; same pattern applies to
        # open-webui.nix + vaultwarden.nix.
        # Serialize concurrent prep — both `-onetouch` and `-mp510`
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
