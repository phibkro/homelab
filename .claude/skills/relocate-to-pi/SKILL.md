---
description: Migrate a service from nori-station to nori-pi using the cross-host split-module pattern. Daemon module on Pi, client/proxy module on every host that talks to it; cross-host references via the `nori.hosts` registry; lanRoute gated on Caddy presence so Pi's Blocky stays in pure forwarder mode. Established by beszel-hub and ntfy-server migrations.
when_to_use: User wants a service to survive station outages or fits the appliance role (observability, alerting, DNS, network plumbing) — phrases like "move <service> to Pi", "relocate <service>", "Pi should run <service>", "<service> should survive station going down", "appliance-side <service>".
---

# Relocate a service to nori-pi

Pattern established by beszel-hub (commit b4499ee) and ntfy-server (commit 9e0b2b6). Use when fate-sharing requires the service to survive station outages — the exception clause is "fate-sharing breaks the function," not "feels lightweight."

## Decision summary up front

1. **Does the service genuinely belong on Pi?** Workhorse-by-default per CLAUDE.md bias. The exception is observability + alerting + DNS + network plumbing — services whose entire reason to exist is to observe / alert / route, which lose their function when the host they monitor goes down. Pi has 8 GiB and anti-write storage; every additional service competes with the observer role.
2. **Split shape**: `modules/server/<service>/{daemon,client}.nix` where the daemon is the actual server (lives on Pi) and the client is the proxy / notification template / agent (lives on every host).
3. **State migration**: usually NOT worth it for non-load-bearing data (metrics, ephemeral caches). Daemon comes up empty and rebuilds from sops + first-use. Document the decision.
4. **Backup decision**: Pi's anti-write posture means `nori.backups.<n>.skip = "..."` for the daemon — host-aware assertion in `modules/effects/backup.nix` enforces this.

## Step-by-step

### 1. Split the existing module

```bash
# Before:
modules/server/<service>.nix         # one file with everything

# After:
modules/server/<service>/
  daemon.nix     # the actual server (or hub, or whatever the daemon is)
  client.nix     # the proxy, notification template, agent — what every host needs
  default.nix    # optional aggregator if both sides go on the same host
```

Folder = coupling (per CONVENTIONS.md "Module structure"). The `daemon.nix`/`client.nix` naming follows the established pattern: beszel uses `{hub,agent}.nix`, ntfy uses `{server,notify}.nix` — pick names that match the service's vocabulary.

### 2. Daemon side (lives on Pi)

```nix
# modules/server/<service>/daemon.nix
{ config, lib, pkgs, ... }:
{
  services.<service> = {
    enable = true;
    # listen on 0.0.0.0:<port> so Caddy on station can reach over tailnet
    host = "0.0.0.0";
    port = N;
  };

  # FS hardening
  nori.harden.<unit> = { };

  # Tailnet exposure for the cross-host Caddy reverse-proxy backend
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ N ];

  # Pi anti-write posture — backup must skip
  nori.backups.<n>.skip = "Hub on appliance host. Pi flash anti-write posture; <reason data is non-load-bearing>. Defer until Pi gains the planned local fast-restore disk repo (see modules/server/backup/restic.nix).";
}
```

### 3. Client side (lives on every host)

```nix
# modules/server/<service>/client.nix
{ config, lib, pkgs, ... }:
{
  # Cross-host lanRoute gated on Caddy presence — only the host running
  # Caddy registers the route. Pi's Blocky stays in pure forwarder mode;
  # the canonical service host (station) owns the *.nori.lan map.
  nori.lanRoutes = lib.mkIf config.services.caddy.enable {
    <short-name> = {
      port = N;
      host = config.nori.hosts.nori-pi.tailnetIp;  # registry, not literal
      monitor = { };
    };
  };

  # Per-host config that varies by hostname (e.g. ntfy notification
  # templates that reference the source host) reads
  # `config.networking.hostName` rather than introducing options.
}
```

The `lib.mkIf config.services.caddy.enable` is load-bearing. Without it, Pi's Blocky would auto-generate a `*.nori.lan` map for the cross-host service, which fights the forwarder-mode design (Pi delegates `*.nori.lan` queries to station's Blocky).

The `host = config.nori.hosts.nori-pi.tailnetIp` is also load-bearing — never use IP literals. The `forbidden-patterns` flake check doesn't currently catch this, but it would be caught at code review and the topology refactor (commit 444423f) was specifically about eliminating IP literals in cross-host refs.

### 4. Update host imports

```nix
# hosts/nori-station/default.nix → modules/server/default.nix bundle
# imports the client side (notify / agent / proxy) automatically.
# DO NOT import the daemon side — station shouldn't be running it.

# hosts/nori-pi/default.nix
imports = [
  ../../modules/server/<service>/daemon.nix
  ../../modules/server/<service>/client.nix  # Pi runs both — agent talks to its own hub, etc.
];
```

Update `modules/server/default.nix` (the workhorse bundle) to import only the client side. Update `hosts/nori-pi/default.nix` (flat imports) to import both daemon + client.

### 5. Per-host config that varies

If the original module branched on hostname (e.g. ntfy's notification template that references the source host's name), keep the branching but use `config.networking.hostName` rather than introducing a new option.

Hardware-specific FS gates (e.g. exposing `/dev/nvidia*` to beszel-agent on GPU hosts only) read existing registries — `config.nori.gpu.nvidiaDevices != [ ]` — rather than per-service flags. The agent's `PrivateDevices` override is the precedent.

### 6. State migration (usually NOT worth it)

For non-load-bearing data (metrics history, ephemeral caches), let the daemon come up empty on Pi. Document the decision in the daemon module's header comment AND in the commit body. Example phrasing: "Migrated from station 2026-04-29. Empty start on Pi: <metric-name> from before <date> are gone; <reason that's acceptable>."

For load-bearing state (auth DB, configuration), copy via:

```bash
# On station, before destroying station's copy:
sudo systemctl stop <service>
sudo rsync -aHX /var/lib/<service>/ nori@nori-pi.saola-matrix.ts.net:/tmp/<service>-migration/

# On Pi:
sudo rsync -aHX /tmp/<service>-migration/ /var/lib/<service>/
sudo chown -R <service>:<service> /var/lib/<service>/    # if static user
sudo systemctl start <service>

# Or for DynamicUser, use /var/lib/private/<service>
```

### 7. Deploy order: Pi first

```bash
# Pi first — daemon is up before station's `services.<service>` config drops out
just remote nori-pi rebuild

# Then station — its modules now omit the daemon side; Caddy starts proxying cross-host
just rebuild
```

Reverse order leaves a window where neither host has the daemon running, which can cause cascading alerts.

### 8. Verify end-to-end

```bash
# Canonical URL exercises DNS → Caddy → cross-host tailnet → daemon all in one
curl -fsS https://<short-name>.nori.lan/v1/health  # or whatever the health endpoint is

# Daemon-side health on Pi
ssh nori@nori-pi.saola-matrix.ts.net 'systemctl is-active <unit> && journalctl -u <unit> -n 20 --no-pager'

# Cross-host firewall — Caddy on station should reach Pi:N
nc -z -w 2 100.100.71.3 N && echo OK
```

### 9. Update CLAUDE.md + commit

Topology section — add the new cross-host split to the existing list (or remove the previous mention if the service moved out of station). Per the "On every structural change" rubric — drift compounds.

Commit message:

```
feat(<scope>): migrate <service> from station to Pi

<reason it belongs on Pi — typically fate-sharing>

── Split-module shape ────────────────────────────────────────────
modules/server/<service>/{daemon,client}.nix.
* daemon.nix on Pi — runs the actual server
* client.nix everywhere — Caddy lanRoute gated on services.caddy.enable
  so only station registers it; backend reads
  config.nori.hosts.nori-pi.tailnetIp from the registry

── State ──────────────────────────────────────────────────────────
<empty start vs migrated; rationale>

── Verification ───────────────────────────────────────────────────
<canonical URL probe + journalctl evidence>
```

## After the third instance

Pattern's at 2/3 (beszel hub, ntfy server). On the third instance, consider extracting `mkCrossHostService` per CLAUDE.md "Rule of three for abstractions". Don't pre-extract — wait for the third concrete use to reveal the actual axis of variation.
