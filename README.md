# nori homelab

Single-user NixOS homelab flake. Two-host topology (`nori-station` built; `nori-pi` deferred — no NixOS-bootable USB SSD yet).

## Where to start

| If you're… | Read |
|---|---|
| New here, want the architecture | `docs/DESIGN.md` |
| Adding a service or making changes | `docs/CONVENTIONS.md` |
| Debugging anything that touches disks, certs, sops, or DynamicUser | `docs/gotchas.md` |
| Resuming work, looking for what's pending | `docs/RESUME.md` |
| An LLM agent picking this up cold | `CLAUDE.md` |

## Active services

All HTTP services live behind Caddy at `https://<name>.nori.lan`. Tailnet-only via Tailscale's DNS push (admin console → DNS → custom nameserver = `100.81.5.122`). Caddy uses an internal CA — install `modules/services/caddy-local-ca.crt` once per device.

| URL | What |
|---|---|
| `https://auth.nori.lan` | Authelia (SSO issuer) |
| `https://chat.nori.lan` | Open WebUI (Authelia SSO working) |
| `https://ai.nori.lan` | Ollama (CUDA, RTX 5060 Ti) |
| `https://media.nori.lan` | Jellyfin |
| `https://metrics.nori.lan` | beszel |
| `https://status.nori.lan` | Gatus (synthetic uptime checks) |
| `https://alert.nori.lan` | local ntfy |
| `smb://nori-station.saola-matrix.ts.net` | Samba (`/mnt/media`, `/srv/share`) |

Background:
- `blocky` — adblock DNS for the tailnet via Tailscale push
- `restic` — daily backups (placeholder local repo for now)
- `btrbk` — daily btrfs subvolume snapshots
- `ntfy` (push to ntfy.sh) — alert delivery for restic/btrbk failures + Gatus probe drops

## Operating

```bash
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
  nori-station/              # bare-metal NixOS host
  vm-test/                   # UTM dry-run target
modules/
  common/                    # cross-host baseline
  services/                  # one file per service
  lib/                       # cross-cutting abstractions (lan-route)
secrets/
  secrets.yaml               # sops-encrypted, committed
  README.md                  # secrets workflow ops doc
.sops.yaml                   # sops policy (recipients + path patterns)
docs/
  DESIGN.md                  # architecture (canonical)
  CONVENTIONS.md             # repo patterns
  gotchas.md                 # landmines
  RESUME.md                  # current state + loose ends
CLAUDE.md                    # agent prompting
```

## Phase status

| Phase | What | State |
|---|---|---|
| 0-3 | Inventory, backups, dry-run install | done |
| 4 | Bare-metal install on nori-station | done |
| 5 | Service migration | in progress (file/AI/media/SSO/observability live; Cloudflare Tunnel deferred) |
| 6 | Hyprland desktop | not started |
| — | `hosts/nori-pi/` | deferred (no USB SSD) |

See `docs/RESUME.md` "Loose ends" for the to-do list.
