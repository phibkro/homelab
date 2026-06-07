{
  lib,
  pkgs,
  ...
}:

let
  # TRaSH-guide-derived quality profiles + custom formats. One config
  # file per *arr instance — recyclarr 8.x rejects "split instances"
  # (multiple configs targeting the same base_url), so the WEB-1080p /
  # WEB-2160p (Sonarr) and HD-Bluray-Web / UHD-Bluray-Web (Radarr)
  # scaffolds from `recyclarr config create -t <template>` are merged
  # by-trash_id into one instance per service.
  #
  # Profiles + custom formats land in Sonarr/Radarr after first sync;
  # operator picks the profile per series/movie via UI. Adding extra
  # CF groups (HDR boost, streaming services, anime tags) means
  # uncommenting entries in the YAML — TRaSH updates the underlying
  # scoring; recyclarr picks it up on next sync.
  configs = [
    ./recyclarr/sonarr.yml
    ./recyclarr/radarr.yml
  ];
  configFlags = lib.concatMapStringsSep " " (f: "--config ${f}") configs;
in
{
  # Recyclarr — syncs TRaSH-guide quality profiles + custom formats into
  # Sonarr and Radarr on a weekly cadence. No UI; pure batch job.
  #
  # ── Bootstrap ────────────────────────────────────────────────────────
  # API keys live in /etc/recyclarr.env (gitignored-.env pattern, NOT
  # sops): mode 0400 root:root, two lines —
  #   SONARR_API_KEY=...
  #   RADARR_API_KEY=...
  # Each *arr's API key is at Settings → General → API Key in their UI,
  # or directly in /var/lib/{sonarr,radarr}/config.xml under <ApiKey>.
  # Sops would be cleaner if we ever rotate often; until then the env
  # file is one-shot operator setup.
  #
  # First sync after rebuild:
  #   sudo systemctl start recyclarr-sync.service
  #   just show-logs recyclarr-sync
  #
  # In Sonarr/Radarr, then set each tracked series/movie to one of the
  # newly-created profiles (`WEB-1080p`, `WEB-2160p`, `HD-Bluray-Web`,
  # `UHD-Bluray-Web`). Recyclarr only creates the profiles + custom
  # formats; assignment per-item stays operator-controlled.
  #
  # ── Cadence ──────────────────────────────────────────────────────────
  # Wednesday 04:30 + ~30min jitter. TRaSH guides update slowly (days-
  # weeks); weekly is plenty. Persistent=true catches missed runs after
  # downtime.

  systemd.services.recyclarr-sync = {
    description = "Sync TRaSH-guide profiles + custom formats into Sonarr/Radarr";
    after = [
      "network-online.target"
      "sonarr.service"
      "radarr.service"
    ];
    wants = [ "network-online.target" ];

    environment = {
      RECYCLARR_CONFIG_DIR = "/var/lib/recyclarr";
    };

    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "recyclarr";
      EnvironmentFile = "/etc/recyclarr.env";
      ExecStart = "${pkgs.recyclarr}/bin/recyclarr sync ${configFlags}";
    };
  };

  systemd.timers.recyclarr-sync = {
    description = "Weekly Recyclarr sync";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed 04:30";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  nori.harden.recyclarr-sync = { };

  nori.backups.recyclarr.skip = "stateless — config in store, cache re-derivable, profile state lives in sonarr/radarr backups";
}
