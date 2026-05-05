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
  server/                     # "this host serves things" — one file per service
    <service>.nix             #   loose: independent services
    <cluster>/                #   folder = tightly-coupled services (arr, backup, beszel, ntfy)
      default.nix
  desktop/                    # "this host has a graphical session" (Hyprland, greetd, ...)
  lib/                        # cross-cutting abstractions
    hosts.nix                 # nori.hosts — topology registry (tailnetIp, lanIp, role)
    lan-route.nix             # nori.lanRoutes — *.nori.lan exposure
    backup.nix                # nori.backups — restic decisions
    gpu.nix                   # nori.gpu.nvidiaDevices — GPU device registry
    harden.nix                # nori.harden — systemd FS-namespace hardening
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

  # Default-deny filesystem access — see "FS hardening" below.
  # Attribute key MUST match the systemd service unit name.
  nori.harden.<service> = {
    binds = [ /* writable host paths */ ];
    readOnlyBinds = [ /* read-only host paths */ ];
    # protectHome = null;  # only when upstream's ProtectHome value is opinionated and you want to leave it alone (rare; see syncthing)
  };

  # LAN exposure — auto-generates Caddy vhost + Blocky DNS + Gatus monitor
  nori.lanRoutes.<short-name> = {
    port = N;
    monitor = { };  # or .path = "/health" if non-default
  };

  # Backup intent (required — `every-service-has-backup-intent` flake check)
  nori.backups.<service>.paths = [ "/var/lib/<service>" ];
  # or for stateless / re-derivable services:
  # nori.backups.<service>.skip = "<reason>";

  # Optional: open backend port directly on tailnet (default: closed)
  # nori.lanRoutes.<short-name>.exposeOnTailnet = true;
}
```

## LAN exposure: `nori.lanRoutes`

Single source of truth for `*.nori.lan` services. One declaration → three things generated:

1. **Caddy vhost** at `<name>.nori.lan` reverse-proxying to backend
2. **Blocky DNS** mapping `<name>.nori.lan` → workhorse LAN IP
3. **Gatus monitor** (if `monitor` is set) probing the backend, alerting via ntfy on failure

See `modules/lib/lan-route.nix` for the schema.

**Naming**: function over brand. `chat`, `ai`, `alert`, `media`, `metrics`, `status` — not `open-webui`, `ollama`, `ntfy`, `jellyfin`, `beszel`, `gatus`. Brand names only when the brand IS the identity (`auth` for Authelia, `samba` if it ever gets routed).

## Network policy: default-deny

- **Tailnet firewall**: only Caddy (`80 + 443`) and Samba (`445`) are open by default. All backend ports closed. Services opt in via `nori.lanRoutes.<name>.exposeOnTailnet = true` for direct port access (rare — Caddy is the canonical entry).
- **Public internet**: nothing exposed yet. Cloudflare Tunnel + Access is the future plan when needed.
- **Localhost**: services bind to `0.0.0.0` so Caddy can reach them; the firewall enforces what's reachable from outside.

## Filesystem hardening: default-deny

The default-deny systemd FS-namespace block (`ProtectHome = mkForce true`, `TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ]`, plus `BindPaths` / `BindReadOnlyPaths` for what's let back in) lives behind the `nori.harden` abstraction in `modules/lib/harden.nix`. One declaration per systemd unit name:

```nix
nori.harden.<unit> = {
  binds         = [ /* writable host paths */ ];
  readOnlyBinds = [ /* read-only host paths */ ];
  protectHome   = true | false | null;  # default true; null skips
};
```

The `every-service-has-fs-hardening` flake check fails the build if any `modules/server/*.nix` is missing a `nori.harden.<n>` declaration (excluded list: aggregators, framework, ntfy/notify, samba's legitimate /srv exception).

Verify a service's effective namespace via `sudo systemctl cat <unit>.service | grep -E '(ProtectHome|TemporaryFileSystem|BindPaths|BindReadOnlyPaths)'`, or `sudo nsenter -t <pid> -m -U -- ls /mnt/` to confirm the live mount namespace shows only the bound paths.

Common shapes:
- **No host access** (the default): most services just need their `/var/lib/<n>` StateDirectory — `nori.harden.<n> = { };`
- **Writable subtree**: e.g. *arr stack hardlinking into /mnt/media/streaming — `binds = [ "/mnt/media/streaming" ];`
- **Read-only subtree**: Jellyfin streaming /mnt/media — `readOnlyBinds = [ "/mnt/media" "/srv/share" ];`
- **Upstream-opinionated ProtectHome**: Syncthing's upstream module sets a specific value; `protectHome = null` skips the override entirely.
- **Composed**: services with extra serviceConfig (CPUQuota, EnvironmentFile, SupplementaryGroups, PrivateDevices) declare those in a sibling `systemd.services.<n>.serviceConfig` block — module merging combines the two.

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

## Authelia OIDC pattern

OIDC clients are auto-generated from `nori.lanRoutes.<n>.oidc`. The
abstraction owns the Authelia client entry, the sops secret(s), and
the env-file template; the consuming service module owns its own
systemd wiring (`EnvironmentFile`, `SupplementaryGroups`) and
non-secret OIDC env vars (provider URL, client_id, etc.).

Hash material lives **only in sops**. Authelia's `template`
config-filter (`X_AUTHELIA_CONFIG_FILTERS=template`, set in
`authelia.nix`) reads the PBKDF2 hash from
`/run/secrets/oidc-<n>-client-secret-hash` at startup and
substitutes it into the YAML config before parsing — zero hash
material in committed Nix. Enforced by the `forbidden-patterns`
flake check (see `flake.nix`); a stray inline `\$pbkdf2-` string
fails `nix flake check`.

### Bootstrap (per new client)

1. **Generate raw + hash:** `just oidc-key <name>`. Output is
   sensitive; lands in your terminal, not in any file or shell
   history. Two values to copy.

2. **Paste both into sops** (`sops secrets/secrets.yaml`):
   ```yaml
   oidc-<name>-client-secret: '<raw — opaque base64-ish blob>'
   oidc-<name>-client-secret-hash: '$pbkdf2-sha512$310000$...'
   ```
   Single-quote the hash so YAML doesn't interpret the `$` chars.
   Single-quote the raw too if it happens to contain YAML-special
   characters — usually safe, but harmless.

3. **Declare the route's OIDC block** in the service's module
   (`modules/server/<svc>.nix`). The service module is the
   single source of truth for the route; co-locate everything
   about that service:
   ```nix
   nori.lanRoutes.<name> = {
     port = N;
     monitor = { };
     oidc = {
       clientName  = "Display Name";
       redirectPath = "/path/the/service/uses";
       # Optional overrides (defaults shown):
       # scopes = [ "openid" "profile" "email" "groups" ];
       # authorizationPolicy = "one_factor";
       # secretEnvName = "OAUTH_CLIENT_SECRET";  # → SSO_CLIENT_SECRET for Vaultwarden, etc.
     };
   };
   ```
   Common `redirectPath` values:
   ```
   Open WebUI:  /oauth/oidc/callback
   PocketBase:  /api/oauth2-redirect
   Vaultwarden: /identity/connect/oidc-signin
   ```

4. **Wire the consuming systemd unit** (in the same module):
   ```nix
   systemd.services.<svc>.serviceConfig = {
     EnvironmentFile = config.sops.templates."oidc-<name>-env".path;
     SupplementaryGroups = [ "keys" ];   # DynamicUser needs this to read /run/secrets/rendered/*
   };
   ```
   Plus non-secret OIDC env vars in `services.<svc>.environment`:
   ```nix
   OPENID_PROVIDER_URL = "https://auth.nori.lan/.well-known/openid-configuration";
   OAUTH_CLIENT_ID     = "<name>";
   OAUTH_PROVIDER_NAME = "Authelia";
   ENABLE_OAUTH_SIGNUP = "True";
   ```
   Service-by-service the env-var names vary (`OAUTH_*` for Open
   WebUI; `OPENID_*` for some; `SSO_*` for Vaultwarden). The
   abstraction handles only the *secret-bearing* var via
   `secretEnvName`; the rest stay in the service module where
   per-service quirks live.

5. **Python services** also set `SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt"` so
   `httpx`/`requests`/`urllib3` (which use `certifi` by default,
   not the system trust store) trust Caddy's local CA when calling
   `https://auth.nori.lan`.

6. **Deploy:** `just rebuild`.

### Web-UI-managed consumers (PocketBase / Beszel)

For services that configure OAuth in their own admin UI rather
than via env vars, only steps 1, 2, and 3 apply — no
EnvironmentFile wiring on the service side. The raw secret sits
at `/run/secrets/oidc-<n>-client-secret` for paste-into-admin
when configuring the consumer. The env-file template still
generates and is just unused; cost is microscopic.

### What stays manual and why

- **PBKDF2 hash generation** — Authelia's hash uses random salt;
  re-running on the same raw produces a different hash. Not
  amenable to declarative regeneration. `just oidc-key` collapses
  the two CLI invocations into one.
- **Per-service systemd unit name + env-var convention** — the
  abstraction can't divine `chat` → `open-webui`, and OIDC
  env-var naming is too varied across services to abstract
  (OAUTH_*, OPENID_*, SSO_*, custom). Both stay in the service
  module where they're discoverable.

### Caddy's local CA

Available in system trust via
`security.pki.certificateFiles = [ ./caddy-local-ca.crt ];` in
`caddy.nix`. `curl` / Go / `openssl` pick it up automatically;
Python's `certifi` doesn't (hence step 5's `SSL_CERT_FILE`).

## Backup correctness: Patterns A / B / C

From `docs/DESIGN.md` L210-289. Choose the right one per service:

| Pattern | When | Implementation |
|---|---|---|
| A: filesystem-only | data isn't a database | restic targets paths directly |
| B: built-in dump | service writes its own SQL dumps (Immich) | restic picks up the dump dir |
| C: external dump pre-restic | sqlite/postgres without internal dump | `backupPrepareCommand` runs `sqlite3 .backup` first |

Restic per-repo declarations live alongside their service modules via `nori.backups.<n>`; cross-cutting infra (sops password, check timers) is in `modules/server/backup/restic.nix`. Repository at `/mnt/backup/<job>` (OneTouch ext4); Hetzner Storage Box still on the roadmap as a second per-job repository for off-site coverage.

## Snapshot policy

`modules/server/backup/btrbk.nix` declares two btrfs subvolume snapshot instances (root + media). Daily by default. Snapshot retention follows DESIGN's tier table.

Both `restic-backups-*` and `btrbk-*` units get `OnFailure = [ "notify@%n.service" ]` so silent failures fire an ntfy alert.

## Commit conventions

- Conventional Commits (`type(scope): summary`)
- Body: explain *why* and what was tried. Reviewers appreciate the workflow narrative.
- Co-authored attribution: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` on agent-driven commits.

## Code style

- `nixfmt` formatting (set as the flake formatter; `pkgs.nixfmt-rfc-style` is now an alias for `pkgs.nixfmt`)
- `statix` for Nix anti-pattern lint
- `deadnix` for unused bindings
- Run via `nix flake check` or pre-commit hooks (`.githooks/pre-commit` skips gracefully if nix isn't on PATH; CI catches what pre-commit skipped)

## Enforcing conventions through code

Rules written as prose drift the moment they're written. Conventions in this repo are encoded as enforcement layers, in order of preference:

### 1. Type system

Use option `type =` constraints first. Free, immediate, error message points at the option itself.

```nix
port = mkOption { type = types.port; ... };       # 0..65535 enforced at eval
scheme = mkOption { type = types.enum [ "http" "https" ]; ... };
```

If the rule fits a type, write the type. Don't restate it in the description.

### 2. Module assertions

Cross-attribute invariants checked at NixOS eval time. Eval fails atomically with the message you wrote.

```nix
assertions = [
  {
    assertion = lib.length ports == lib.length (lib.unique ports);
    message = "lanRoutes have duplicate backend ports.";
  }
];
```

See `modules/lib/lan-route.nix` for the live examples (port uniqueness, name regex, redirectPath shape). Use when a rule depends on multiple options together — derived properties, uniqueness across attrs, conditional requirements.

### 3. Custom flake checks

Derivations under `checks.${system}.<n>` in `flake.nix`. Run via `nix flake check`. Arbitrary shell, runs grep/find/scripts over the source tree. Use for repo-wide rules that don't live inside the module system.

```nix
forbidden-patterns = pkgs.runCommandLocal "forbidden-patterns" {
  nativeBuildInputs = [ pkgs.gnugrep ];
} ''
  cd ${./.}
  if grep -rn 'pattern' modules/ ; then
    echo "✗ explanation of what's wrong"
    exit 1
  fi
  touch $out
'';
```

See `flake.nix` `forbidden-patterns` for the live examples (no inline pbkdf2 hashes, no caddy/blocky bypass). Use for "no X in path Y" style rules. If the rule needs AST awareness, graduate to a tree-sitter-nix wrapper — not currently present, introduce only when grep stops being enough.

### 4. CI gate

`.github/workflows/check.yml` runs `nix flake check` on every push and pull_request. Backstop for cases where pre-commit was skipped: commits from a Mac without nix on PATH (the most common case here), `git commit --no-verify`, agents that bypass the hook. The check itself is just `nix flake check --print-build-logs`; everything in layers 1–3 runs through it.

### When to add a rule

When you write the words "we should always..." or "don't ever..." in prose, ask:

- Single option's value? → **type**.
- Consistency across options? → **module assertion**.
- Forbidden text pattern in source files? → **flake check (grep)**.
- Forbidden semantic pattern? → **flake check** (introspect via `nix eval`) or AST-aware check.

If none fit, the rule is judgment — that's what code review is for. Don't write it down; it'll rot.

### When NOT to add a rule

- The rule's false positives outweigh real catches.
- The cost of the constraint exceeds the cost of fixing the violation.
- Only one person in the project ever cares; let that person enforce it in review.

**A check earns its keep when it would have caught a real mistake, not a hypothetical one.** Add when violations occur or are imminent — not preemptively.

## Module structure: concerns compose host identity

`modules/<concern>/` directories represent host roles. A host's identity is the sum of which concerns it imports plus its hardware:

- `modules/common/` — universal infra. Every host imports this. Contains: base system, user accounts, Tailscale, sops, plus the `lib/` option modules (`lan-route.nix`, `backup.nix`) that any module on the host can populate.
- `modules/server/` — *this host serves things*. Caddy, Authelia, *arr stack, backups, media, monitoring, etc. Hosts that import it become servers; hosts that omit it aren't.
- `modules/desktop/` — *this host has a graphical session*. Hyprland, greetd, audio, applications.
- `modules/lib/` — option-defining modules (the `nori.lanRoutes` and `nori.backups` schemas + assertions). Imported by `common/` so every host has the options available; populated opt-in via service modules.

A typical host file:

```nix
# hosts/nori-station/default.nix
imports = [
  inputs.disko.nixosModules.disko
  ../../modules/common
  ../../modules/server
  ../../modules/desktop
  ./hardware.nix
  ./disko.nix
];
```

Reading this answers "what kind of machine is `nori-station`?" at a glance. `nori-pi` lives today as `common +` *flat imports of specific server modules* (Blocky, Gatus, Beszel hub+agent, ntfy server+notify) — the bundle import (`../../modules/server`) is too coarse for the appliance role. Future `nori-laptop` will be `common + desktop` (no server services).

**Within `modules/server/`, folders signal coupling, not categorization.** Tightly-coupled clusters get their own folder + `default.nix`:

- `modules/server/arr/` — Sonarr/Radarr/Lidarr/Bazarr/Jellyseerr/Prowlarr/qBittorrent. They reference each other via API and share `/mnt/media/streaming` via the `media` group + `arr/shared.nix` tmpfiles.
- `modules/server/backup/` — `restic.nix` + `verify.nix` + `btrbk.nix`. They share `/mnt/backup`, the `restic-password` sops secret, and the `notify@` failure pipeline.

Loose services that just happen to be in the same conceptual area (e.g. Beszel, Gatus, Glance, ntfy — all observability-shaped but mutually independent) stay flat at `server/`'s top level.

**Adding a service**: see CLAUDE.md's "How to add a new service" for the full procedure. Short version: drop the file in `modules/server/` (loose) or in an existing cluster folder (coupled), append it to the relevant `default.nix`, declare `nori.lanRoutes.<n>` + `nori.backups.<n>`, deploy.

With the second server (nori-pi) live, `modules/server/default.nix` stays as the workhorse bundle (station imports it whole). The appliance picks individual files via flat imports because its service set is small + opinionated. If a third server lands or Pi's import list grows past ~10 files, subdivide into sub-concerns then — not preemptively.

Cross-host services (services that live on one host but are reverse-proxied or read by another) follow the split-module pattern documented in `CLAUDE.md` "How to relocate a service to nori-pi". Precedents: `modules/server/beszel/{hub,agent}.nix`, `modules/server/ntfy/{server,notify}.nix`.

## Dev workflow

`Justfile` at repo root for common workflows. Install: `brew install just` on macOS, `pkgs.just` already in `modules/common/base.nix`.

```
just                          # default: rebuild via rsync + nh os switch
just <recipe> [<host>]        # all recipes accept optional host arg
just status                   # failed units + disk + restic/btrbk timer summary
just logs <unit>              # last 50 journal lines
just check                    # nix flake check
just deploy                   # git push + nh os switch from origin (no rsync)
just rollback                 # previous generation
just backup <repo>            # immediately run restic-backups-<repo>
just snapshots <repo>         # list restic snapshots
just --list                   # all recipes
```

Default `host` is `nori-station`; pass `nori-laptop` (etc.) to deploy elsewhere when those hosts land. SSH targets via Tailnet MagicDNS (`<host>.saola-matrix.ts.net`).

`nh os switch` is the rebuild engine — replaces `nixos-rebuild`. Internal sudo (don't prefix with `sudo`); shows ADDED/REMOVED/CHANGED package diff before activating.
