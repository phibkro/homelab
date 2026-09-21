# Accepted recovery observations. Workload placement and backup mechanics stay
# derived from service manifests and evaluated backup jobs.
{
  authelia-service = {
    scope = "service";
    workload = "authelia";
    report = "docs/archive/reports/2026-09-21-authelia-recovery-drill.md";
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "integrity"
      "startup"
      "endpoint"
      "oidc-discovery"
    ];
  };

  immich-export = {
    scope = "service";
    workload = "immich";
    report = "docs/archive/reports/2026-09-21-immich-export-recovery-drill.md";
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "hash-equality"
      "import"
      "row-equality"
    ];
  };

  beszel-service = {
    scope = "service";
    workload = "beszel-hub";
    report = "docs/archive/reports/2026-09-21-pi-service-recovery-closure.md";
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "integrity"
      "startup"
      "endpoint"
      "data-block-integrity"
    ];
  };

  caddy-service = {
    scope = "service";
    workload = "caddy";
    report = "docs/archive/reports/2026-09-21-pi-service-recovery-closure.md";
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "validation"
      "endpoint"
      "data-block-integrity"
    ];
  };

  jellyfin-metadata = {
    scope = "service";
    workload = "jellyfin";
    report = "docs/archive/reports/2026-09-21-jellyfin-metadata-recovery-drill.md";
    observedAt = "2026-09-21";
    maxAgeDays = 120;
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
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "import"
      "migration"
      "startup"
      "endpoint"
    ];
  };

  ntfy-service = {
    scope = "service";
    workload = "ntfy-server";
    report = "docs/archive/reports/2026-09-21-ntfy-recovery-drill.md";
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "integrity"
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
    observedAt = "2026-09-21";
    maxAgeDays = 120;
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
    observedAt = "2026-09-21";
    maxAgeDays = 120;
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
    observedAt = "2026-09-21";
    maxAgeDays = 120;
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
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "hash-equality"
      "metadata"
    ];
  };

  vector-pipeline = {
    scope = "service";
    host = "pi";
    backupJob = "vector";
    model = "filesystem";
    report = "docs/archive/reports/2026-09-21-pi-service-recovery-closure.md";
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "validation"
      "startup"
      "endpoint"
      "data-block-integrity"
    ];
  };

  victorialogs-service = {
    scope = "service";
    workload = "victorialogs-server";
    report = "docs/archive/reports/2026-09-21-pi-service-recovery-closure.md";
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "startup"
      "endpoint"
      "query"
      "data-block-integrity"
    ];
  };

  victoriametrics-service = {
    scope = "service";
    workload = "victoriametrics";
    report = "docs/archive/reports/2026-09-21-pi-service-recovery-closure.md";
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "startup"
      "endpoint"
      "query"
      "data-block-integrity"
    ];
  };

  vaultwarden-database = {
    scope = "service";
    workload = "vaultwarden";
    report = "docs/archive/reports/2026-09-21-vaultwarden-sqlite-recovery-drill.md";
    observedAt = "2026-09-21";
    maxAgeDays = 120;
    gates = [
      "restore"
      "import"
      "migration"
      "endpoint"
    ];
  };
}
