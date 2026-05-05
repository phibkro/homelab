# nori homelab

Single-user NixOS homelab flake. Two live hosts: `nori-station` (workhorse — Caddy, Authelia, all GPU/media/state-heavy services) and `nori-pi` (appliance — observability hub, alert plane, DNS forwarder, tailnet routing).

## Where to start

| If you're… | Read |
|---|---|
| New here, want the architecture | `docs/DESIGN.md` |
| Adding a service or making changes | `docs/CONVENTIONS.md` |
| Debugging anything that touches disks, certs, sops, or DynamicUser | `docs/gotchas.md` |
| Resuming work, want current state + outstanding items | `CLAUDE.md` |

## Active services

All HTTP services live behind Caddy at `https://<name>.nori.lan`. Resolution: Blocky returns nori-station's LAN IP (`192.168.1.181`), so LAN clients hit Caddy directly with no tailnet hop. Off-LAN tailnet clients reach the same address via nori-pi's subnet route advertisement (`192.168.1.0/24`); needs `--accept-routes` on the client. DNS is served by nori-pi's Blocky (Tailscale admin console → DNS → custom nameserver = `100.100.71.3`); LAN-only devices need their DNS pointed at nori-pi's LAN IP (`192.168.1.225`). Caddy uses an internal CA — install `modules/server/caddy-local-ca.crt` once per device.

The live inventory is the `nori.lanRoutes` attrset in `config`. Static lists drift; query the source of truth instead:

```bash
ssh nori@nori-station.saola-matrix.ts.net \
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

# Sync to nori-station and rebuild
rsync -aH --delete --exclude=.git . nori@192.168.1.181:/tmp/nix-migration/
ssh nori@192.168.1.181 'cd /tmp/nix-migration && sudo nixos-rebuild switch --flake .#nori-station'

# Validate before pushing
nix flake check     # eval + statix + deadnix + format
nix fmt             # auto-format

# Edit secrets
sops secrets/secrets.yaml
```

The pre-commit hook (`.githooks/pre-commit`) runs `nix flake check` automatically when any `.nix` or `flake.lock` file is staged — catches eval errors, statix anti-patterns, deadnix unused bindings, and unformatted files. Skips gracefully if `nix` isn't on PATH (most commits originate from the Mac without nix; the host catches issues at rebuild time anyway). Bypass for emergency commits with `git commit --no-verify`.

## Quality gates

`nix flake check` runs four checks:
1. **Eval** — `nixosConfigurations.<host>` evaluate cleanly (catches type errors, undefined options, etc.)
2. **statix** — Nix anti-pattern lint
3. **deadnix** — unused-binding detection
4. **format** — `nixfmt-rfc-style` compliance check

Run before any commit that touches `.nix` files.

## Repo shape

```
flake.nix                    # entry, inputs, host definitions, checks
hosts/
  nori-station/              # bare-metal x86_64 workhorse
  nori-pi/                   # Raspberry Pi 4 aarch64 appliance
  vm-test/                   # UTM dry-run target
modules/
  common/                    # cross-host baseline (every host)
  server/                    # "this host serves things" concern
  desktop/                   # "this host has a graphical session"
  lib/                       # cross-cutting abstractions (lan-route, backup, gpu)
secrets/
  secrets.yaml               # sops-encrypted, committed
  README.md                  # secrets workflow ops doc
.sops.yaml                   # sops policy (recipients + path patterns)
docs/
  DESIGN.md                  # architecture (canonical)
  CONVENTIONS.md             # repo patterns
  gotchas.md                 # landmines
CLAUDE.md                    # agent prompting + current state + outstanding items
```

## Phase status

Phases 0–6 done. Phase 7 (tightening + new capabilities) substantively done — backup abstraction + 14-service coverage, type-level enforcement, DynamicUser symlink trap caught, OIDC auto-gen with zero hash material in committed Nix, Immich GPU acceleration with resource caps, `nori-pi` brought up as the appliance host with cross-host service split (Beszel hub + ntfy server). Live state + outstanding items in `CLAUDE.md`; canonical phasing rationale in `docs/DESIGN.md`.
