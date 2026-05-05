---
description: Add a new self-hosted service to this homelab NixOS flake — wires the upstream module enable, FS hardening (`nori.harden`), Caddy + DNS exposure (`nori.lanRoutes`), backup intent (`nori.backups`), GPU access (`nori.gpu`), OIDC SSO, and import plumbing in the right order with the right decisions.
when_to_use: The user asks to install, deploy, set up, or run a new service on the homelab — phrases like "add <service>", "let's set up <X>", "I want <Y> running", "deploy a new service", "install <service>", "bring up <something> on the homelab". Also when a new file is being created under `modules/server/`.
---

# Add a new homelab service

Authoritative procedure. Three flake checks (`every-service-has-fs-hardening`, `every-service-has-backup-intent`, `forbidden-patterns`) plus per-module assertions enforce the schema; this skill is the playbook + decision tree before the build catches you.

## Decision summary up front

For the user's request, work out:
1. **Is it loose or part of an existing cluster?** Loose → `modules/server/<service>.nix`. Cluster (arr / backup / beszel / ntfy) → `modules/server/<cluster>/<service>.nix`. Folders signal coupling, not categorization.
2. **What FS access does it need?** None (90% of services), writable subtree (e.g. *arr writes /mnt/media/streaming), read-only subtree (e.g. Jellyfin streams /mnt/media), or upstream-opinionated ProtectHome (Syncthing).
3. **Is it HTTP-exposed via Caddy?** If yes → `nori.lanRoutes.<short-name>`. Pick a function-named subdomain (`media` not `jellyfin`).
4. **Does it need SSO?** If yes → run `just oidc-key <short-name>`, paste into sops, add `oidc = { ... }` to the lanRoute, wire EnvironmentFile.
5. **Does it need GPU?** If yes → `accelerationDevices = config.nori.gpu.nvidiaDevices` (or the systemd `DeviceAllow` equivalent).
6. **Backup pattern?** A (filesystem-only), B (built-in dump path), or C2 (prepareCommand). Or `skip = "<reason>"` if stateless / re-derivable / covered elsewhere.
7. **DynamicUser?** `/var/lib/<n>` is a SYMLINK; back up `/var/lib/private/<n>` instead. The symlink-trap assertion in `modules/lib/backup.nix` lists known DynamicUser services and catches mistakes at eval.

## Step-by-step

### 1. File location

```bash
# Loose:
modules/server/<service>.nix

# Cluster:
modules/server/<cluster>/<service>.nix
```

Read `modules/server/default.nix` (loose imports) or `modules/server/<cluster>/default.nix` (cluster imports) — you'll add the new file there in step 7.

### 2. Enable the upstream module

```nix
{ config, lib, pkgs, ... }:
{
  services.<service> = {
    enable = true;
    user = "<service>";       # if static-user
    group = "<service>";
    openFirewall = false;     # always — Caddy is the canonical entry
    # service-specific config
  };
}
```

If the service runs as `DynamicUser`, note the unit name — its state lives at `/var/lib/private/<unit>` (with a `/var/lib/<unit>` symlink). Add it to the `dynamicUserServices` list in `modules/lib/backup.nix` if it's a new DynamicUser service so the symlink-trap assertion catches mistakes.

### 3. FS hardening — REQUIRED (`every-service-has-fs-hardening` flake check)

```nix
nori.harden.<unit-name> = {
  binds         = [ /* writable host paths */ ];   # rare
  readOnlyBinds = [ /* read-only host paths */ ];  # rare
  # protectHome = null;  # only when upstream's value is opinionated and forcing it would regress (Syncthing precedent)
};
```

The unit name MUST match the systemd service unit (e.g. `seerr` not `jellyseerr`; `authelia-main` not `authelia`). Multi-unit services declare separate entries (Immich has `immich-server` + `immich-machine-learning`).

For services that need extra serviceConfig keys (CPUQuota, EnvironmentFile, SupplementaryGroups, PrivateDevices), declare those in a sibling `systemd.services.<unit>.serviceConfig` block — module merging combines them with the abstraction's output.

### 4. LAN exposure (HTTP services only)

```nix
nori.lanRoutes.<short-name> = {
  port = N;
  monitor = { };  # default probe at /
  # monitor.path = "/api/health";  # override for non-default health endpoint
};
```

Run `just ports` first to see allocated ports. Pick a port that doesn't collide; the eval-time uniqueness assertion catches mistakes.

Naming: function over brand (`chat` not `open-webui`, `media` not `jellyfin`, `ai` not `ollama`). Brand only when the brand IS the identity (`auth` for Authelia).

### 5. SSO (if needed)

```bash
just oidc-key <short-name>
# outputs raw + PBKDF2 hash; copy both
sops secrets/secrets.yaml
# paste:
#   oidc-<short-name>-client-secret: <raw>
#   oidc-<short-name>-client-secret-hash: <hash>
```

Add the OIDC block to the lanRoute:

```nix
nori.lanRoutes.<short-name>.oidc = {
  clientName = "<Display Name>";        # shown on Authelia consent screen
  redirectPath = "/oauth/oidc/callback"; # service-specific (Open WebUI uses this; Vaultwarden /identity/connect/oidc-signin; PocketBase /api/oauth2-redirect)
  # secretEnvName = "SSO_CLIENT_SECRET";  # default OAUTH_CLIENT_SECRET; override per service
  # scopes = [ "openid" "profile" "email" "groups" "offline_access" ]; # add offline_access for refresh tokens (Vaultwarden needs this)
  # authorizationPolicy = "two_factor";  # default one_factor
};
```

Wire the env file on the systemd unit:

```nix
systemd.services.<unit>.serviceConfig = {
  EnvironmentFile = config.sops.templates."oidc-<short-name>-env".path;
  SupplementaryGroups = [ "keys" ];   # required for DynamicUser; harmless for static users
};
```

The Authelia client list is auto-assembled from all `nori.lanRoutes.*.oidc` blocks. Hash material lives only in sops; Authelia's `template` config-filter expands `{{ secret "..." }}` at startup.

### 6. Backup intent — REQUIRED (`every-service-has-backup-intent` flake check)

Pick the pattern:

```nix
# Pattern A — filesystem-only:
nori.backups.<n>.paths = [ "/var/lib/<service>" ];

# Pattern B — built-in dump (service writes its own dump on schedule):
nori.backups.<n>.paths = [ "/var/lib/<service>" "/var/lib/<service>/backups" ];

# Pattern C2 — prepare command before restic snapshot:
nori.backups.<n> = {
  paths = [ "/var/lib/<service>" "/var/backup/<service>" ];
  prepareCommand = ''
    if [ -f /var/lib/<service>/db.sqlite3 ]; then
      mkdir -p /var/backup/<service>
      ${pkgs.sqlite}/bin/sqlite3 /var/lib/<service>/db.sqlite3 \
        ".backup '/var/backup/<service>/db.sqlite3'"
    fi
  '';
  timer = "*-*-* 04:30:00";  # stagger if needed
};

# Opt out:
nori.backups.<n>.skip = "<one-line reason: stateless / re-derivable / covered elsewhere>";
```

DynamicUser symlink: `/var/lib/<n>` is a symlink for DynamicUser services; restic stores symlinks AS symlinks (0-byte snapshot). Use `/var/lib/private/<n>` instead. The assertion in `modules/lib/backup.nix` catches this at eval if you target the symlink.

Appliance hosts (Pi) cannot use `paths` — they must `skip` (anti-write storage posture). The host-aware assertion in `modules/lib/backup.nix` enforces this.

### 7. GPU access (if needed)

```nix
services.<service>.accelerationDevices = config.nori.gpu.nvidiaDevices;
# OR for systemd directly:
systemd.services.<unit>.serviceConfig.DeviceAllow = config.nori.gpu.nvidiaDevices;
```

Single source of truth in `modules/lib/gpu.nix` — host's hardware.nix sets `nori.gpu.nvidiaDevices`; consumers reference that. Empty list on hosts without a GPU; opt-in services pass through cleanly.

### 8. Wire imports

```bash
# Loose service:
$EDITOR modules/server/default.nix    # add ./<service>.nix to imports list

# Cluster service:
$EDITOR modules/server/<cluster>/default.nix
```

### 9. Build + verify

```bash
nix flake check                                 # validates all derivations + eval
just rebuild                                    # build + activate locally
systemctl is-active <unit>                      # process is up
sudo systemctl cat <unit>.service | grep -E '(ProtectHome|TemporaryFileSystem|Bind)'   # verify FS hardening
curl -sk https://<short-name>.nori.lan -m 5 | head -3                                  # HTTP smoke test
```

If a flake check fails, the message lists the offending file(s) with what's missing. Common failure modes:
- forgot `nori.harden.<n>` → `every-service-has-fs-hardening` fails with the file path
- forgot `nori.backups.<n>` → `every-service-has-backup-intent` fails
- port collision → eval-time assertion in `modules/lib/lan-route.nix`
- DynamicUser symlink in backup paths → eval-time assertion in `modules/lib/backup.nix`

### 10. First-run setup

If the service has a web UI, head to `https://<short-name>.nori.lan` and walk through the wizard. Document the wizard steps as a header comment in the module file (see existing modules for the pattern — sonarr, radarr, etc.).

### 11. Commit

```bash
git add -A
git commit -m "feat(<scope>): <terse summary>"
```

Conventional Commits style. Body explains the why if non-obvious. Co-author tag per repo convention.
