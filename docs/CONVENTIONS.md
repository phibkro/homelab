# Conventions

Repository-wide patterns. Established by lived experience over the
Phase 5 service migration. Follow these unless you have a clear
reason not to (and document the reason inline if you deviate).

## Module structure

```
hosts/<host>/                 # per-host configs (default.nix, hardware.nix, disko.nix)
modules/
  common/                     # cross-host baseline (base, users, tailscale, sops)
    default.nix               # imports the others
  services/                   # one file per service module
    <service>.nix
  lib/                        # cross-cutting abstractions
    lan-route.nix             # the LAN exposure abstraction
secrets/
  secrets.yaml                # sops-encrypted, committed
  README.md                   # ops doc for the secrets workflow
.sops.yaml                    # sops policy (which keys decrypt what)
```

A service module owns *everything* about its service: the upstream module's `enable`, its env vars, hardening, lan-route declaration, OIDC integration, backup config. Don't fan out a service across multiple files.

## Service module template

```nix
{ config, lib, pkgs, ... }:
{
  # Upstream module
  services.<service> = {
    enable = true;
    # ...service-specific config...
  };

  # Default-deny filesystem access (see "FS hardening" below)
  systemd.services.<service>.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
    BindReadOnlyPaths = [ /* opt in to host paths the service needs */ ];
  };

  # LAN exposure — auto-generates Caddy vhost + Blocky DNS + Gatus monitor
  nori.lanRoutes.<short-name> = {
    port = N;
    monitor = { };  # or .path = "/health" if non-default
  };

  # Optional: open backend port directly on tailnet (default: closed)
  # nori.lanRoutes.<short-name>.exposeOnTailnet = true;
}
```

## LAN exposure: `nori.lanRoutes`

Single source of truth for `*.nori.lan` services. One declaration → three things generated:

1. **Caddy vhost** at `<name>.nori.lan` reverse-proxying to backend
2. **Blocky DNS** mapping `<name>.nori.lan` → tailnet IP
3. **Gatus monitor** (if `monitor` is set) probing the backend, alerting via ntfy on failure

See `modules/lib/lan-route.nix` for the schema.

**Naming**: function over brand. `chat`, `ai`, `alert`, `media`, `metrics`, `status` — not `open-webui`, `ollama`, `ntfy`, `jellyfin`, `beszel`, `gatus`. Brand names only when the brand IS the identity (`auth` for Authelia, `samba` if it ever gets routed).

## Network policy: default-deny

- **Tailnet firewall**: only Caddy (`80 + 443`) and Samba (`445`) are open by default. All backend ports closed. Services opt in via `nori.lanRoutes.<name>.exposeOnTailnet = true` for direct port access (rare — Caddy is the canonical entry).
- **Public internet**: nothing exposed yet. Cloudflare Tunnel + Access is the future plan when needed.
- **Localhost**: services bind to `0.0.0.0` so Caddy can reach them; the firewall enforces what's reachable from outside.

## Filesystem hardening: default-deny

Every service module's `serviceConfig` includes:

```nix
ProtectHome = lib.mkForce true;          # /home and /root invisible
TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];  # tmpfs over these dirs
BindReadOnlyPaths = [ /* opt in */ ];    # bind-mount only what's needed back in
```

Verify via `sudo nsenter -t <pid> -m -U -- ls /mnt/` from the host — should show empty or only the bound paths.

`mkForce` for `ProtectHome` is needed when the upstream module already sets it as `true` (boolean) — Nix sees `true` and `"yes"` as conflicting definitions.

Some services need access to specific host paths:
- Jellyfin: `/mnt/media` (read media library) + `/srv/share` (optional)
- Samba: `/mnt/media`, `/srv/share` (its job is to expose them)
- Most others: empty `BindReadOnlyPaths` — they only need `/var/lib/<service>/`

## Secrets: sops-nix patterns

### Single-value secrets

```yaml
# secrets.yaml
restic-password: <random>
oidc-chat-client-secret: <random>
```

```nix
sops.secrets.restic-password = {
  mode = "0440";
  owner = "<service-user>";  # static user, or:
  group = "keys";              # for DynamicUser services
};

services.foo.passwordFile = config.sops.secrets.restic-password.path;
```

### Env-file format (for `EnvironmentFile=`)

When a service consumes secrets via env vars, use sops templates. Two key things:

1. The template content uses sops placeholder substitution at activation time
2. The format is `KEY=VALUE` (env-file syntax — **`=`, not `:`**, and YAML block-string in sops adds a trailing newline that env-file expects)

```yaml
# secrets.yaml — env file format
gatus-env: |
  NTFY_CHANNEL=nori-claude-jhiugyfthgcv
```

```nix
# Or, when combining multiple sops secrets into one env file:
sops.templates."open-webui-oauth-env" = {
  mode = "0440";
  group = "keys";
  content = ''
    OAUTH_CLIENT_SECRET=${config.sops.placeholder.oidc-chat-client-secret}
  '';
};

systemd.services.open-webui.serviceConfig = {
  EnvironmentFile = config.sops.templates."open-webui-oauth-env".path;
  SupplementaryGroups = [ "keys" ];  # DynamicUser needs this for /run/secrets read
};
```

### DynamicUser caveats

NixOS services using `DynamicUser=yes` (open-webui, ollama, ntfy-sh, beszel-hub, gatus) get a fresh UID per session. Implications:

- Can't use `chown <name>:<name>` — those users don't exist statically
- `chown --reference=<existing-file>` to copy ownership from a sibling
- `SupplementaryGroups = [ "keys" ]` to grant access to /run/secrets/* (mode 0440 root:keys)
- StateDirectory mounts `/var/lib/<name>` from `/var/lib/private/<name>` — see `docs/gotchas.md`

## Authelia OIDC pattern (manual until auto-gen lands)

Per service that opts in to SSO:

1. Generate raw secret + PBKDF2 hash:
   ```bash
   ssh nori@192.168.1.181 'nix shell nixpkgs#openssl nixpkgs#authelia --command bash -c "
     SECRET=\$(openssl rand -base64 32 | tr -d \"=+/\")
     echo \"raw: \$SECRET\"
     authelia crypto hash generate pbkdf2 --variant sha512 --iterations 310000 --password \"\$SECRET\"
   "'
   ```
2. Add raw to sops as `oidc-<name>-client-secret`
3. Append client entry to `modules/services/authelia.nix` `identity_providers.oidc.clients`:
   ```nix
   {
     client_id = "<name>";
     client_name = "<Display Name>";
     client_secret = "<paste-the-pbkdf2-hash>";
     public = false;
     authorization_policy = "one_factor";
     redirect_uris = [ "https://<name>.nori.lan/<callback-path>" ];
     scopes = [ "openid" "profile" "email" "groups" ];
   }
   ```
   Hash inline is OK — it's one-way, safe to commit.
4. Wire the consuming service:
   - Set OIDC env vars (provider URL, client ID, scopes) directly in `services.<service>.environment`
   - Inject client_secret via sops template + EnvironmentFile (see open-webui example)
   - Python services: also set `SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt"` so they trust Caddy's CA

The Caddy CA is in system trust via `security.pki.certificateFiles = [ ./caddy-local-ca.crt ];` in `caddy.nix`. curl/Go/openssl pick it up automatically; Python's `certifi` doesn't (hence `SSL_CERT_FILE`).

## Backup correctness: Patterns A / B / C

From `docs/DESIGN.md` L210-289. Choose the right one per service:

| Pattern | When | Implementation |
|---|---|---|
| A: filesystem-only | data isn't a database | restic targets paths directly |
| B: built-in dump | service writes its own SQL dumps (Immich) | restic picks up the dump dir |
| C: external dump pre-restic | sqlite/postgres without internal dump | `backupPrepareCommand` runs `sqlite3 .backup` first |

Restic backup config is in `modules/services/backup-restic.nix`. Currently a placeholder local repo; the principle holds when real targets land.

## Snapshot policy

`modules/services/btrbk.nix` declares two btrfs subvolume snapshot instances (root + media). Daily by default. Snapshot retention follows DESIGN's tier table.

Both `restic-backups-*` and `btrbk-*` units get `OnFailure = [ "notify@%n.service" ]` so silent failures fire an ntfy alert.

## Commit conventions

- Conventional Commits (`type(scope): summary`)
- Body: explain *why* and what was tried. Reviewers appreciate the workflow narrative.
- Co-authored attribution: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` on agent-driven commits.

## Code style

- `nixfmt-rfc-style` formatting (set as the flake formatter)
- `statix` for Nix anti-pattern lint
- `deadnix` for unused bindings
- Run via `nix flake check` (when CI gate lands) or pre-commit hooks

## What gets imported where

- `modules/common/` is loaded by every host. Things that are universal: nix settings, locale, base packages, firewall enabled, sshd, tailscale, sops scaffolding.
- `modules/services/<x>.nix` is loaded by individual hosts that need it. Per-host opt-in via `imports = [ ... ]` in `hosts/<host>/default.nix`.
- `modules/lib/<x>.nix` defines abstractions. Imported once by hosts that use them.

When in doubt, prefer per-host opt-in over universal inclusion. Adding a service to `common/` makes every future host inherit it.
