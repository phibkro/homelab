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

# Presentation-only projection for a future authenticated frontend
nix build .#portal-json --no-link --print-out-paths

# Workload names selected for one NixOS host
nix eval .#nixosConfigurations.<host>.config.nori.inventory.currentWorkloads

# Resolved workload declarations available to that host
nix eval .#nixosConfigurations.<host>.config.nori.inventory.workloads

# Complete route projection available to runtime adapters
nix eval .#nixosConfigurations.<host>.config.nori.inventory.routes

# Where each route's backend runs
nix eval .#lib.noriInventory.routes \
  --apply 'with builtins; mapAttrs (_: route: route.host) it'

# Per-route exposure summary
nix eval .#lib.noriInventory.routes \
  --apply 'with builtins; mapAttrs (_: route: { inherit (route) host port audience reachability; }) it'
```

Cross-host services use the split-module pattern (`docs/reference/topology.md` § cross-host services).

Every independently placed workload has a pure `manifest.nix` and a concrete
realization such as `nixos.nix`. The manifest owns catalog, endpoint, listener,
audience, and presentation metadata. Runtime adapters consume the resolved
`nori.inventory` projection; they do not repeat route names, hostnames, or
ports. The adapter owns units, hardening, backup intent, and implementation-
internal ports. Physical paths and filesystem identities live in
`infra/<machine>/`. The compiler imports only runtimes selected by
service-owned placement selectors.

### About Immich's Postgres

`services.immich.database.enable = true` provisions a Postgres instance owned by Immich, separate from `services.postgresql`. NixOS 25.11+ uses VectorChord (replacing pgvecto-rs) and Postgres 17 by default. Immich's own database management writes periodic dumps to `/var/lib/immich/backups/`. Backup Pattern B picks up those dumps rather than running an external `pg_dump`.

## Backup-correctness patterns

Four patterns cover files, built-in exports, PostgreSQL, and SQLite. All active
jobs use `nori.backups.<name>`. The patterns differ in the selected data and the
preparation that runs before Restic.

| Pattern | When | Implementation | Example |
|---|---|---|---|
| **A: Filesystem-only** | Data is not a database | Restic targets paths directly | Jellyfin library, Samba shares, `/home`, `/srv/share` |
| **B: Built-in dump** | Service writes its own SQL dumps | Restic includes the dump directory | Immich |
| **C1: External dump (PostgreSQL)** | System PostgreSQL without an internal dump | `services.postgresqlBackup` then Restic | Miniflux, Paperless |
| **C2: External dump (SQLite)** | Service writes SQLite without an internal dump | `prepareCommand` uses `VACUUM INTO` and `flock` | Vaultwarden, Navidrome |

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
  databases = [ "miniflux" ];
  startAt = "*-*-* 03:30:00";
  pgdumpOptions = "--no-owner";
};
nori.backups.miniflux.include = [
  "/var/backup/postgresql/miniflux.sql.gz"
];
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

`prepareCommand` runs as `ExecStartPre` on each configured target unit. Destination selection comes from `inventory/backup.nix`; retain flock to serialize any concurrent dump callers. `VACUUM INTO` requires destination absent — that's why `rm -f` precedes it.

Runtime check: `just test-backups` asserts per-target snapshot ≤25h.

### Recovery contracts

Do not maintain a second per-service pattern table here. Workload manifests
declare their recovery model and backup-job edge. The
[generated recovery view](../generated/recovery-evidence.md) joins those
contracts with evaluated backup paths, targets, exclusions, and recorded
evidence reports.

Cross-cutting host data, such as user-data roots, enters that view through the
evidence registry because it has no workload manifest. Services with an
intentional backup skip, such as re-downloadable Ollama models, do not declare a
backup recovery contract.

New services pick a pattern at onboarding (`/add-service`). Pattern C2 services
MUST use the flock-wrapped canonical implementation. Concurrent dump callers
must not corrupt the staging file.

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

Runtime credentials for workstation-hosted applications live in
`secrets/workstation-runtime.yaml`. The file's recipient set matches the
workstation runtime authority. `secretspec.toml` provides the masked operator
interface for setting and rotating its values.

Live worked example: `services/filmder/manifest.nix` declares its
endpoint and governed `legacy-host-build` artifact contract;
`services/filmder/nixos.nix` consumes that contract for the systemd
build and serving realization. Filmder and Heim are the only mutable-source
exceptions. Their manifests name an owner, reason, removal trigger, and test;
new product deployments should consume immutable artifacts instead.

## Desktop settings service

The `nori-desktop-settings` system service runs as the dedicated
`nori-desktop-settings` UID. It is the only writer for the versioned profile,
preview receipts, and apply jobs. Its private `/run/nori-desktop-settings/backend.sock`
socket has mode `0600`. Credential-checked `/run/nori-desktop-settings/public.sock`
has mode `0660` and accepts requests only from `nori`.

Desktop Settings and Vicinae use the same typed CLI and the sole fixed public
ingress path; neither has an XDG-runtime socket fallback. The profile limit is
32 KiB, half of the 64 KiB IPC frame limit. Each saved command has a 4 KiB
limit. The remaining frame space holds contracts, jobs, and observations. They
do not edit profile files or reload Waybar. The persistent nori runtime agent
is the only user-side component allowed to request the named polkit activation,
reload Waybar, and submit a bounded surface observation.
Only isolated internal TypeScript tests may inject `CliRuntime`; every installed
CLI, saved-command, and runtime-agent wrapper sets
`NORI_DESKTOP_SETTINGS_SOCKET` to that public path.

The authority builds only from the approved immutable Nix source and stops at
authorization. The root helper re-reads the durable apply ID and validates the
source, profile revision, profile hash, canonical profile, and artifact identity.
Following the NixOS activation order, it first registers the artifact in
`/nix/var/nix/profiles/system` with the pinned `nix-env`, then runs its fixed
switch program. It returns the resolved active and boot-default paths and only
reports success when both equal the approved artifact.

Waybar state is untrusted surface evidence from the `nori` runtime agent.
The same UID can modify that surface, so the report cannot prove process identity.
Reconciliation records the report, but only independently validated active generation
identity can make a job `active` or `failed`.
The authority-owned `/run/nori-desktop-settings` directory has mode `0710`.
Its shared group can traverse it, but cannot create or unlink socket entries.
The authority can bind and replace its own sockets.
The activation lock has mode `0640`, owner `root`, and a separate authority group.
Only the authority UID belongs to that group. The desktop user cannot block it with an advisory lock.

Waybar reads the resolved generated profile after activation. The operator
must activate a workstation generation.
