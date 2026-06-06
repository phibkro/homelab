# nori homelab

Single-user NixOS homelab flake. Two live hosts: `workstation` (workhorse — Caddy, Authelia, all GPU/media/state-heavy services) and `pi` (appliance — observability hub, alert plane, DNS forwarder, tailnet routing).

## Where to start

| If you're… | Read |
|---|---|
| New here, want the routing map | `CLAUDE.md` |
| Wanting the vocabulary + mental models | `docs/CONCEPTS.md` |
| Adding a service or making changes | `docs/MODULES.md` + `docs/SERVICES.md` |
| Wiring topology / placement | `docs/TOPOLOGY.md` |
| Touching storage, backups, snapshots | `docs/STORAGE.md` |
| Touching network, lanRoutes, Authelia, DNS | `docs/NETWORK.md` |
| Debugging a known landmine (NVMe, Caddy CA, sops, DynamicUser, …) | `.claude/skills/gotcha-*/SKILL.md` (~35 individual auto-loaded skills) |
| Resuming work, forward plan | `docs/ROADMAP.md` |

## Active services

All HTTP services live behind Caddy at `https://<name>.nori.lan`. Resolution: Blocky returns workstation's LAN IP (`192.168.1.181`), so LAN clients hit Caddy directly with no tailnet hop. Off-LAN tailnet clients reach the same address via pi's subnet route advertisement (`192.168.1.0/24`); needs `--accept-routes` on the client. DNS is served by pi's Blocky (Tailscale admin console → DNS → custom nameserver = `100.100.71.3`); LAN-only devices need their DNS pointed at pi's LAN IP (`192.168.1.225`). Caddy uses an internal CA — install `modules/services/caddy-local-ca.crt` once per device.

The live inventory is the `nori.lanRoutes` attrset in `config`. Static lists drift; query the source of truth instead:

```bash
ssh nori@workstation.saola-matrix.ts.net \
  'nix eval --raw /run/current-system/etc/nixos -A config.nori.lanRoutes --apply builtins.attrNames'
```

Background services not exposed via Caddy:
- `blocky` — adblock DNS for the tailnet via Tailscale push (`:53`)
- `samba` — SMB shares for `/mnt/media`, `/srv/share` (`:445`, not HTTP)
- `restic` — daily backups to OneTouch (lazy-mounted)
- `btrbk` — hourly/daily btrfs subvolume snapshots
- `ntfy` — alert delivery: ntfy.sh push + local `alert.nori.lan` for restic/btrbk/Gatus failures

## Operating

```bash
# One-time per fresh clone — enable the pre-commit hook
git config core.hooksPath .githooks

# Edit on Mac (here), push to GitHub
git push

# Sync to workstation and rebuild
just remote workstation rebuild
# or directly:
rsync -aH --delete --exclude=.git . nori@192.168.1.181:/tmp/nix-migration/
ssh nori@192.168.1.181 'cd /tmp/nix-migration && just rebuild'

# Validate before pushing
nix flake check     # eval + statix + deadnix + format
nix fmt             # auto-format

# Edit secrets
sops secrets/secrets.yaml
```

The pre-commit hook (`.githooks/pre-commit`) runs `nix flake check` automatically when any `.nix` or `flake.lock` file is staged. Skips gracefully if `nix` isn't on PATH (most commits originate from the Mac without nix; the host catches issues at rebuild time anyway). Bypass for emergency commits with `git commit --no-verify`.

## Quality gates

`nix flake check` runs the standard Nix lints (statix, deadnix, nixfmt format check) plus the repo-specific guard derivations in `flake.nix`'s `checks.${system}` attrset. Run `nix flake show .#checks` for the current set; categories:

- **Eval-time module assertions** — port uniqueness, exclusive paths/skip, host-aware appliance constraints, …
- **Pattern enforcement** — `every-service-has-<X>` derivations fail if any `modules/services/*.nix` omits a required declaration
- **Anti-pattern grep guards** — `forbidden-patterns` fails if banned strings appear

Adding a new rule: `docs/ENFORCEMENT.md` § decision tree.

## Repo shape

```
flake.nix                    # entry, inputs, host definitions, checks
machines/
  workstation/               # bare-metal x86_64 workhorse
  pi/                        # Raspberry Pi 4 aarch64 appliance
  macbook/                   # Intel Mac, standalone home-manager only
  core.nix                   # shared interactive-user home-manager baseline
modules/
  common/                    # cross-host system baseline
  effects/                   # cross-cutting `nori.<X>` declarative options
  server/                    # "this host serves things" concern
  desktop/                   # "this host has a graphical session"
  dev/                       # dev-shell fragments + composer
  claude-code/               # operator's global Claude config
secrets/
  secrets.yaml               # sops-encrypted, committed
  apps.yaml                  # personal-app tokens; sops-encrypted
.sops.yaml                   # sops policy (recipients + path patterns)
docs/
  CONCEPTS.md INVARIANTS.md  # tier-1 reference (vocab, mental models, load-bearing claims)
  PROCEDURES.md ROADMAP.md   # tier-1 reference (skill index, forward plan)
  TOPOLOGY.md STORAGE.md     # tier-2 reference (one job each)
  NETWORK.md SERVICES.md
  MODULES.md ENFORCEMENT.md
  RECOVERY.md RATIONALES.md
  decisions/                 # ADRs (dated)
  runbooks/                  # per-failure step-by-step
  superpowers/               # per-feature specs and plans
.claude/skills/              # procedure skills + gotcha skills (load on demand)
CLAUDE.md                    # tier-0 entrypoint — read order + hard rules + bias + how-to-operate
```

## Status

Phases 0–7 done — backup + FS-hardening + LAN-route abstractions cover every service module with build-time enforcement, type-level constraints with module assertions, DynamicUser symlink trap caught, OIDC auto-gen with zero hash material in committed Nix, Immich CUDA ML + NVENC with resource caps, `pi` brought up as the appliance host with cross-host service split (Beszel hub + ntfy server). Channel pinned to stable `nixos-26.05` since 2026-06-03. Forward plan in `docs/ROADMAP.md`; durable rationales in `docs/RATIONALES.md`.
