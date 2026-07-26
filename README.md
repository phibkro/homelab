# nori homelab

Single-user NixOS homelab flake. Four NixOS hosts on a residential LAN + tailnet, plus a Mac on standalone home-manager:

| Host | Role | Runs |
|---|---|---|
| **pi** | always-on appliance (aarch64) | HTTP entry plane (Caddy + Authelia + Blocky-authoritative on `*.home.phibkro.org`), observability hub (Beszel + Gatus + VictoriaMetrics/Logs), alert plane (ntfy), Tailscale subnet+exit |
| **aurora** | always-on family vault (x86_64) | `/mnt/family/*` irreplaceable data + family-tier backends (Vaultwarden, Immich, Calibre-web, Komga, Navidrome, Radicale, Miniflux, Glance, Heim, Filmder, Grafana), OneTouch restic target |
| **workstation** | sleep-friendly compute (x86_64) | Ollama (GPU), Jellyfin (NVENC), `*arr` stack + qBittorrent, `@downloads`, daily-driver desktop. Cold replica of `/mnt/family/*` on MP510 (btrbk receive) |
| **pavilion** | agent quarantine (x86_64) | impermanence-rooted; nixpkgs-agent / sandboxed Claude and Codex work, headless |

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
| Operating the Genexis router programmatically | `.claude/skills/manage-genexis-juci/` or `.codex/skills/manage-genexis-juci/` |
| Resuming work, forward plan | `docs/roadmap.md` |

## Active services

All HTTP services live behind Caddy at `https://<name>.home.phibkro.org`, LE-signed via ACME DNS-01 against Cloudflare — trusted by every modern device with no per-device CA install (ADR-0004). Legacy `http://*.nori.lan` URLs 301-redirect transitionally while bookmarks migrate; legacy HTTPS URLs cannot redirect without an untrusted private-CA handshake.

Resolution path: Blocky on pi is authoritative for `*.home.phibkro.org` on the LAN/tailnet (resolves to pi's LAN IP — Caddy's vhost). Pi's `cloudflare-ddns` derives exact DNS-only IPv4 records from routes explicitly marked `reachability = "internet"` (currently `media`, `requests`, and `audio`) and keeps them pointed at the residential WAN address; other routes remain address-gated to LAN/tailnet clients. LAN clients hit Caddy directly with no tailnet hop. Off-LAN tailnet clients reach the same address via pi's subnet-route advertisement (`192.168.1.0/24`); needs `--accept-routes` on the client. Tailnet DNS comes from pi's Blocky (Tailscale admin console → DNS → custom nameserver = `100.100.71.3`); LAN-only devices need their DNS pointed at pi's LAN IP (`192.168.1.225`). See ADR-0006 for the exposure boundary and deployment checks.

The live catalog is compiled from the secret-free manifests in `inventory/` and
injected into every NixOS host as `nori.inventory`. Static lists drift; query or
build a projection of the source of truth:

```bash
nix build .#inventory-json --no-link --print-out-paths
nix build .#status-json --no-link --print-out-paths
nix build .#portal-json --no-link --print-out-paths
```

Background services not exposed via Caddy:
- `blocky` — adblock DNS for the tailnet via Tailscale push (`:53`)
- `cloudflare-ddns` — reconciles exact internet-route A records every five minutes (DNS-only; ownership-isolated; no wildcard, proxy, or AAAA)
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

# See which builds and activations a change would affect (read-only)
just plan-deploy origin/main

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

```text
flake.nix flake.lock         # inputs and thin flake-parts composition
flake-parts/                 # checks, packages, apps, dev shell, host outputs
inventory/                   # pure hosts, profiles, workload manifests, datasets, site
modules/
  machines/                  # NixOS factory plus hardware/storage realizations
  profiles/                  # reusable system capability compositions
  services/                  # manifest/runtime workload pairs; arr remains one coupled cluster
  infra/                     # typed platform effects and their adapters
  home/                      # Home Manager capabilities, profiles, provider-neutral skills, agent tooling, rice
tests/                       # evaluation, VM, fixtures, and operator-triggered tests
scripts/                     # checks, deployment planning, and operator utilities
secrets/                     # sops-encrypted values; never part of inventory projections
docs/
  glossary.md invariants.md  # vocabulary and enforced load-bearing claims
  roadmap.md                 # outcome backlog
  specs/ decisions/          # accepted designs and durable decisions
  reference/ runbooks/       # current truth and executable operations
  plans/ reports/            # retained execution plans and retrospectives
.claude/skills/ .codex/skills/ # generated provider skill surfaces; repository procedures remain under .claude
```

## Status

NixOS channel pinned to stable `nixos-26.05` since 2026-06-03. Backup + FS-hardening + LAN-route abstractions cover every service module with build-time enforcement; OIDC auto-gen with zero hash material in committed Nix; aurora migration (P10–P14) landed mid-June 2026 — family-tier backends moved off workstation, family vault on Toshiba HDD with restic to OneTouch + nightly btrbk replication to workstation's MP510; pi promoted to HTTP entry plane (Caddy + Authelia + Blocky-authoritative + LE wildcard cert on `*.home.phibkro.org` per ADR-0003/0004). Forward plan in `docs/roadmap.md`; durable rationales in `docs/decisions/0000-rationales.md`.
