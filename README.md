# nori homelab

Single-user NixOS homelab flake. Four NixOS hosts on a residential LAN + tailnet, plus a Mac on standalone home-manager:

| Host | Role | Runs |
|---|---|---|
| **pi** | always-on appliance (aarch64) | HTTP entry plane (Caddy + Authelia + Blocky-authoritative on `*.home.phibkro.org`), observability hub (Beszel + Gatus + VictoriaMetrics/Logs), alert plane (ntfy), Tailscale subnet+exit |
| **aurora** | always-on family vault (x86_64) | `/mnt/family/*` irreplaceable data + family-tier backends (Vaultwarden, Immich, Calibre-web, Komga, Navidrome, Radicale, Miniflux, Glance, Heim, Filmder, Grafana), OneTouch restic target |
| **workstation** | sleep-friendly compute (x86_64) | Ollama (GPU), Jellyfin (NVENC), `*arr` stack + qBittorrent, `@downloads`, daily-driver desktop. Cold replica of `/mnt/family/*` on MP510 (btrbk receive) |
| **pavilion** | agent quarantine (x86_64) | impermanence-rooted; hermes / nixpkgs-agent / sandboxed claude work, headless |
| **macbook** | daily-driver laptop (intel x86_64) | standalone home-manager only — not under the flake's `nixosConfigurations` |

## Where to start

| If you're… | Read |
|---|---|
| New here, want the routing map + hard rules + bias | `CLAUDE.md` |
| Wanting the vocabulary + mental models | `docs/glossary.md` |
| Curious which load-bearing claims are enforced (and which drift silently) | `docs/invariants.md` |
| Adding a service or making changes | `docs/reference/module-authoring.md` + `docs/reference/services.md` |
| Wiring topology / placement | `docs/reference/topology.md` |
| Touching storage, backups, snapshots | `docs/reference/storage.md` |
| Touching network, lanRoutes, Authelia, DNS | `docs/reference/network.md` |
| Debugging a known landmine (NVMe, Caddy CA, sops, DynamicUser, …) | `.claude/skills/gotcha-*/SKILL.md` (auto-loaded on trigger) |
| Resuming work, forward plan | `docs/roadmap.md` |

## Active services

All HTTP services live behind Caddy at `https://<name>.home.phibkro.org`, LE-signed via ACME DNS-01 against Cloudflare — trusted by every modern device with no per-device CA install (ADR-0004). Legacy `*.nori.lan` URLs 301-redirect transitionally while family bookmarks migrate.

Resolution path: Blocky on pi is authoritative for `*.home.phibkro.org` on the LAN/tailnet (resolves to pi's LAN IP — Caddy's vhost). Public DNS for the same names has no A records, so the homelab is unreachable from the internet. LAN clients hit Caddy directly with no tailnet hop. Off-LAN tailnet clients reach the same address via pi's subnet-route advertisement (`192.168.1.0/24`); needs `--accept-routes` on the client. Tailnet DNS comes from pi's Blocky (Tailscale admin console → DNS → custom nameserver = `100.100.71.3`); LAN-only devices need their DNS pointed at pi's LAN IP (`192.168.1.225`).

The live inventory is the `nori.lanRoutes` attrset on whichever host runs Caddy (pi). Static lists drift; query the source of truth:

```bash
ssh nori@pi.saola-matrix.ts.net \
  'nix eval --raw /run/current-system/etc/nixos -A config.nori.lanRoutes --apply builtins.attrNames'
```

Background services not exposed via Caddy:
- `blocky` — adblock DNS for the tailnet via Tailscale push (`:53`)
- `samba` — SMB shares for `/mnt/media` (workstation), `/mnt/family/*` (aurora), `/srv/share` (`:445`, not HTTP)
- `restic` — daily backups to OneTouch (aurora) + MP510 (workstation)
- `btrbk` — hourly/daily snapshots + nightly aurora → workstation `/mnt/family/*` replication
- `syncthing` — bidirectional sync on workstation and aurora (phone music → library/music, etc.)
- `ntfy` — alert delivery: ntfy.sh push for restic / btrbk / Gatus failures; local `alert.home.phibkro.org` for the per-host `notify@` template

## Operating

Primary dev host is **workstation** (Zed remote from Mac over SSH, persistent clone at `~/Downloads/homelab`). The Mac keeps a clone at `~/Documents/nix-migration` for offline edits.

```bash
# One-time per fresh clone — enable the pre-commit hook
git config core.hooksPath .githooks

# Local-by-default — builds whichever host you're sitting on
just rebuild

# Remote: rsync to /tmp/nix-migration/ on the target and run `just rebuild` there
just remote pi rebuild
just remote aurora rebuild
just remote workstation rebuild

# Validate before pushing
nix flake check     # eval + statix + deadnix + format + repo-specific guards
nix fmt             # auto-format

# Edit secrets (sops opens $EDITOR on the decrypted YAML)
sops secrets/secrets.yaml
```

The pre-commit hook (`.githooks/pre-commit`) runs `nix flake check` automatically when any `.nix` or `flake.lock` file is staged. It skips gracefully if `nix` isn't on PATH (Mac commits without nix installed; the host catches issues at rebuild time anyway). Bypass for emergency commits with `git commit --no-verify` — CI is the backstop.

Push to `origin/main` is the deploy boundary; any host can `git pull && just rebuild`. Agents do not push to `origin/main` without operator approval — see CLAUDE.md § "Push gate".

## Quality gates

`nix flake check` runs the standard Nix lints (statix, deadnix, nixfmt format check) plus the repo-specific guard derivations in `flake.nix`'s `checks.${system}` attrset. Run `nix flake show .#checks` for the current set; categories:

- **Eval-time module assertions** — port uniqueness, exclusive paths/skip, host-aware appliance constraints, …
- **Pattern enforcement** — `every-service-has-<X>` derivations fail if any `modules/services/*.nix` omits a required declaration
- **Anti-pattern grep guards** — `forbidden-patterns`, `doc-coherence`, `routing-coherence` (scripts under `scripts/checks/`)

Adding a new rule: `docs/invariants.md` § decision tree.

## Repo shape

```
flake.nix flake.lock         # entry, inputs, host registry, checks
CLAUDE.md                    # routing + hard rules + bias + how-to-operate
Justfile                     # local-by-default commands; `just remote <host> <cmd>` wraps any
machines/
  pi/  aurora/  workstation/ # NixOS hosts under nixosConfigurations
  pavilion/
  macbook/                   # Intel Mac, standalone home-manager only
modules/
  common/                    # cross-host system baseline
  effects/                   # cross-cutting `nori.<X>` declarative options
  services/                  # one file per service module
  desktop/                   # "this host has a graphical session"
  dev/                       # dev-shell fragments + composer
home/
  claude-code/               # operator's global Claude config (skills, settings, SOUL.md)
  desktop/                   # home-manager desktop fragments
  hermes/                    # operator-side hermes-agent config
  core.nix pc.nix            # shared interactive-user baseline
scripts/
  checks/                    # bodies for the flake-check derivations
  generate-oidc-key.sh       # ad-hoc operator scripts
secrets/
  secrets.yaml apps.yaml     # sops-encrypted, committed
.sops.yaml                   # sops policy (recipients + path patterns)
docs/
  glossary.md  invariants.md # mandatory: vocab + load-bearing claims
  roadmap.md                 # forward plan
  reference/                 # topic-triggered: topology, storage, network, services, …
  decisions/                 # ADRs (0000 = rationales meta-index)
  plans/  specs/  reports/   # multi-phase forward work / design specs / after-action narratives
  runbooks/                  # per-incident recovery procedures
  installs/                  # bare-metal + VM bring-up + agent-onboarding test
.claude/skills/              # procedure skills + gotcha skills (load on demand)
```

## Status

NixOS channel pinned to stable `nixos-26.05` since 2026-06-03. Backup + FS-hardening + LAN-route abstractions cover every service module with build-time enforcement; OIDC auto-gen with zero hash material in committed Nix; aurora migration (P10–P14) landed mid-June 2026 — family-tier backends moved off workstation, family vault on Toshiba HDD with restic to OneTouch + nightly btrbk replication to workstation's MP510; pi promoted to HTTP entry plane (Caddy + Authelia + Blocky-authoritative + LE wildcard cert on `*.home.phibkro.org` per ADR-0003/0004). Forward plan in `docs/roadmap.md`; durable rationales in `docs/decisions/0000-rationales.md`.
