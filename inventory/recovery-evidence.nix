# Accepted recovery observations. Workload placement and backup mechanics stay
# derived from service manifests and evaluated backup jobs.
{
  immich-export = {
    scope = "service";
    workload = "immich";
    report = "docs/archive/reports/2026-09-21-immich-export-recovery-drill.md";
    gates = [
      "restore"
      "hash-equality"
      "import"
      "row-equality"
    ];
  };

  jellyfin-metadata = {
    scope = "service";
    workload = "jellyfin";
    report = "docs/archive/reports/2026-09-21-jellyfin-metadata-recovery-drill.md";
    gates = [
      "restore"
      "integrity"
      "startup"
      "endpoint"
    ];
  };

  miniflux-database = {
    scope = "service";
    workload = "miniflux";
    report = "docs/archive/reports/2026-09-21-miniflux-postgresql-recovery-drill.md";
    gates = [
      "restore"
      "import"
      "migration"
      "startup"
      "endpoint"
    ];
  };

  pi-host = {
    scope = "host";
    host = "pi";
    model = "filesystem";
    backupJob = "pihole";
    report = "docs/archive/reports/2026-09-21-pi-host-reconstruction-drill.md";
    gates = [
      "convergence"
      "idempotence"
      "restore"
      "reboot"
      "endpoint"
    ];
  };

  pihole-service = {
    scope = "service";
    workload = "pihole";
    report = "docs/archive/reports/2026-09-21-pihole-recovery-drill.md";
    gates = [
      "restore"
      "integrity"
      "startup"
      "endpoint"
    ];
  };

  stremio-identity = {
    scope = "service";
    workload = "stremio";
    report = "docs/archive/reports/2026-09-21-stremio-files-recovery-drill.md";
    gates = [
      "restore"
      "startup"
      "endpoint"
    ];
  };

  user-data = {
    scope = "data";
    host = "workstation";
    backupJob = "user-data";
    model = "filesystem";
    report = "docs/archive/reports/2026-09-21-user-data-recovery-drill.md";
    gates = [
      "restore"
      "hash-equality"
      "metadata"
    ];
  };

  vaultwarden-database = {
    scope = "service";
    workload = "vaultwarden";
    report = "docs/archive/reports/2026-09-21-vaultwarden-sqlite-recovery-drill.md";
    gates = [
      "restore"
      "import"
      "migration"
      "endpoint"
    ];
  };
}
