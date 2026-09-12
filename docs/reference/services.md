---
summary: The "how to wire a service" reference — backup-correctness patterns
  (A/B/C), observability + alert plane, monitored conditions and alert delivery.
  The live catalog is derived from code, not enumerated here.
---

# Services

Workstation uses native NixOS modules where available. Pi services are owned by Ansible roles, including their container and systemd configuration. Placement and naming follow the topology + audience models in `docs/reference/topology.md` + `docs/reference/network.md`.

## Catalog

The live catalog is the pure inventory projection, not this doc. Enumerating in prose drifts the moment anything moves between hosts; query the source instead:

```bash
# Complete public-safe inventory as JSON
nix build .#inventory-json --no-link --print-out-paths

# Presentation-only projections for future frontends
nix build .#status-json --no-link --print-out-paths
nix build .#portal-json --no-link --print-out-paths

# Per-host selected workloads
nix eval .#nixosConfigurations.<host>.config.nori.inventory.currentWorkloads

# Global public-safe workload catalog (placement, tags, endpoints)
nix eval .#nixosConfigurations.<host>.config.nori.inventory.workloads

# Where each route's backend runs (the placement decisions):
nix eval .#nixosConfigurations.workstation.config.nori.lanRoutes \
  --apply 'with builtins; mapAttrs (_: r: r.runsOn) it'

# Per-route exposure summary (audience, port, monitor):
nix eval .#nixosConfigurations.workstation.config.nori.lanRoutes \
  --apply 'with builtins; mapAttrs (_: r: { inherit (r) runsOn port audience; }) it'
```

Cross-host services use the split-module pattern (`docs/reference/topology.md` § cross-host services).

Every independently placed workload has a pure `manifest.nix` and a concrete
realization such as `nixos.nix`. The manifest owns catalog, endpoint, audience,
and presentation metadata; the realization owns upstream service configuration,
secrets, units, hardening, backup intent, and backend-local effects. Physical
paths and filesystem identities live in `infra/<machine>/`. The inventory
compiler imports only realizations selected by explicit host placement.

### About Immich's Postgres

`services.immich.database.enable = true` provisions a Postgres instance owned by Immich, separate from `services.postgresql`. NixOS 25.11+ uses VectorChord (replacing pgvecto-rs) and Postgres 17 by default. Immich's own database management writes periodic dumps to `/var/lib/immich/backups/`. Backup Pattern B picks up those dumps rather than running an external `pg_dump`.

## Backup-correctness patterns

Three flavors depending on service type. All use `services.restic.backups.<n>`; the differences are in *what they back up* and *what runs before the backup*.

| Pattern | When | Implementation | Example |
|---|---|---|---|
| **A: Filesystem-only** | data isn't a database | restic targets paths directly | Jellyfin lib, Samba shares, `/home`, `/srv/share` |
| **B: Built-in dump** | service writes its own SQL dumps | restic picks up the dump dir | Immich |
| **C1: External dump (Postgres)** | system Postgres without internal dump | `services.postgresqlBackup` + restic picks up the dump dir | shared Postgres |
| **C2: External dump (SQLite)** | service writes SQLite without internal dump | `backupPrepareCommand = sqlite3 .backup` on the restic job | Open WebUI |

### Pattern A — filesystem-only

```nix
nori.backups.user-data = {
  include = [ "/home" "/srv/share" "/srv/nori" ];
  tier = "user";  # drives default retention curve
};
# With OneTouch enabled, generates `restic-backups-user-data-onetouch.service`.
```

Don't write `services.restic.backups.<n>` directly — `nori.backups.<n>` is the homelab abstraction; generators expand it into the configured target units + the `every-service-has-backup-intent` flake check coverage.

### Pattern B — built-in dump (Immich)

The directory is included in `/var/lib`; restic of `/var/lib/immich` plus the upload directories is sufficient *if and only if* Immich's internal backup is enabled and the timer beat the restic timer.

```nix
nori.backups.immich = {
  include = [
    "/var/lib/immich/backups"   # SQL dumps (consistent point-in-time)
    "/var/lib/immich/upload"    # user uploads
    "/var/lib/immich/library"   # imported library
    "/var/lib/immich/profile"   # user profiles
  ];
  tier = "irreplaceable";
  timer = "*-*-* 04:00:00";  # after Immich's nightly dump beats restic's
};
```

### Pattern C1 — `services.postgresqlBackup`

```nix
services.postgresqlBackup = {
  enable = true;
  databases = [ "openwebui" ];
  startAt = "*-*-* 03:30:00";
  pgdumpOptions = "--no-owner";
  location = "/var/backup/postgresql";
};
# Then restic backs up /var/backup/postgresql alongside other paths.
```

### Pattern C2 — `prepareCommand` with VACUUM INTO + flock (SQLite)

⚠ Two traps caught in production:

| Trap | Fix | Memory entry |
|---|---|---|
| sqlite3 CLI's `.backup` ignores `busy_timeout` (hard-coded ~2.5s retry) → "database is locked" on the first concurrent writer | Use `VACUUM INTO` + `PRAGMA busy_timeout` (regular SQL, honours the pragma) | [[sqlite-backup-vacuum-into]] |
| Historical dual-target restic units fired in the same minute → both run `prepareCommand` → race on `.tmp` → "table … already exists" | Wrap rm/sqlite/mv in `flock` (file-descriptor form, subshell-scoped) | [[pattern-c2-sqlite-race-flock]] |

Canonical implementation: `services/navidrome/nixos.nix`.

```nix
nori.backups.navidrome = {
  include = [ "/var/lib/navidrome" "/var/backup/navidrome" ];
  prepareCommand = ''
    if [ -f /var/lib/navidrome/navidrome.db ]; then
      mkdir -p /var/backup/navidrome
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
  timer = "*-*-* 04:45:00";
};
```

`prepareCommand` runs as `ExecStartPre` on each configured target unit. OneTouch is the planned target, currently disabled; retain flock to serialize any concurrent dump callers. `VACUUM INTO` requires destination absent — that's why `rm -f` precedes it.

Runtime check: `just test-backups` asserts per-target snapshot ≤25h.

### Pattern selection cheat sheet

| Service | Pattern | Rationale |
|---|---|---|
| Jellyfin | A | Library DB is SQLite but rebuilds from media; non-critical |
| Immich | B | Built-in dump mechanism |
| Open WebUI | C2 | SQLite, no internal dump |
| Vaultwarden | C2 | SQLite (diesel migrations); race fix applied |
| Navidrome | C2 | SQLite (goose migrations); canonical impl reference |
| Ollama | A | Models are re-downloadable |
| Tailscale | A | State files |
| `/home`, `/srv/share`, `/srv/nori` | A (via `nori.backups.user-data`) | No databases |

New services pick a pattern at onboarding (`/add-service`). Pattern C2 services MUST use the flock-wrapped canonical impl — concurrent dump callers must not corrupt the staging file.

## Observability and alerting

```mermaid
flowchart TB
  subgraph workhorse[workhorse hosts]
    WS[workstation]
  end
  subgraph appliance[pi - appliance tier]
    VM[VictoriaMetrics<br/>:8428]
    VL[VictoriaLogs<br/>:9428]
    GA[Gatus]
    BES[Beszel hub]
  end
  WS -- node-exporter:9100<br/>process-exporter:9256 --> VM
  WS -- journald via vector --> VL
  GA -- mutual probe --> WS
  WS -. Grafana queries .-> VM
  WS -. Grafana queries .-> VL
  Pi[heartbeat] --> HC[healthchecks.io]
  GA -- alert --> Public[ntfy.sh public]
  notify[notify@ template<br/>per-host] --> Public
```

| Plane | Tool | Where | Why |
|---|---|---|---|
| **Metrics (system)** | Beszel hub + agent | pi (hub); workhorse hosts (agent) | Forensics: when workstation hangs, Pi's hub keeps recording up to last poll |
| **Metrics (TSDB)** | VictoriaMetrics | pi | Scrapes gatus + node-exporter + process-exporter; 14d retention |
| **Logs (TSDB)** | VictoriaLogs | pi | Aggregates journald via vector shipper; 14d retention. `just query-logs <LogsQL>` |
| **Per-process RSS** | process-exporter | workstation | Leak hunter; pi VM scrapes. See [[workstation-leak-hunting]] |
| **Synthetic checks** | Gatus | pi | Mutual probes; declarative attrset → YAML. Replaced Uptime Kuma |
| **Dashboards** | Grafana | workstation | VM + VL as datasources; per-host system + gatus dashboards |
| **Alert delivery** | ntfy.sh **public** | every host | `notify@<unit>.service` POSTs directly; channel-secret in sops. Pi-local authenticated ntfy serves the agent alert route |
| **Dead-man-switch** | healthchecks.io | pi → external | 60s ping; alerts off-host if pi dies. SPOF mitigation |
| **Runtime test** | `just test-observability` | operator-triggered | Asserts VM targets up + per-host series + heartbeat <90s + zero failing probes. See `docs/reference/runtime-tests.md` |

### Monitored conditions

| Condition | Source | Severity |
|---|---|---|
| Filesystem >80% full | Beszel | Warn |
| Filesystem >90% full | Beszel | Urgent |
| SMART status changes | systemd timer | Urgent |
| Service down (HTTP / TCP probe) | Gatus | Urgent |
| Tailscale connectivity loss | systemd timer | Urgent |
| restic backup job failure | restic systemd unit (`OnFailure → notify@`) | Urgent |
| btrbk snapshot job failure | btrbk systemd unit | Warn |
| Sustained high CPU/memory | Beszel | Warn |

### Alert delivery

| Type | Channel | Trigger |
|---|---|---|
| Real-time, low priority | ntfy default topic | Warnings |
| Real-time, high priority | ntfy urgent topic | Service down, drive failing, backup failed |
| Routine summary | Email digest (deferred) | All metrics summarized; SMTP via Gmail app password when set up |

Email digest deferred. When it lands: Gmail SMTP with app password (sufficient for machine-generated reports; Proton Bridge's complexity isn't warranted for non-private content).

## Self-deployed apps

`secrets/apps.yaml` (separate sops file from `secrets/secrets.yaml`) holds tokens for the operator's personal apps deployed on the homelab. Per-secret `sopsFile = ../../secrets/apps.yaml` override on the consuming module.

Naming convention: agnostic (`tmdb-token`, not `filmder-tmdb-token`) when multiple projects could plausibly share the same key.

Live worked example: `services/filmder/manifest.nix` declares its
endpoint and governed `legacy-host-build` artifact contract;
`services/filmder/nixos.nix` consumes that contract for the systemd
build and serving realization. Filmder and Heim are the only mutable-source
exceptions. Their manifests name an owner, reason, removal trigger, and test;
new product deployments should consume immutable artifacts instead.

## Desktop settings service

The `nori-desktop-settings` system service, running as the dedicated
`nori-desktop-settings` UID, is the only writer for the versioned profile,
preview receipts, and apply jobs. Its private backend socket is not user
accessible. A credential-checked Unix ingress accepts requests only from
`nori`.

Desktop Settings and Vicinae use the same typed CLI and service snapshot.
They do not edit profile files or reload Waybar. The persistent nori runtime
agent is the only user-side component allowed to request the named polkit
activation, reload Waybar, and submit a bounded surface observation.

The authority builds only from the approved immutable Nix source and stops at
authorization. The root helper re-reads the durable apply ID and validates the
source, profile revision, profile hash, canonical profile, and artifact
identity. The authority independently validates active generation metadata
before it records the user's Waybar observation as active or failed.

Waybar reads the resolved generated profile after activation. The operator
must activate a workstation generation.
