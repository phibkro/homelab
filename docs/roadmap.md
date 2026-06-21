---
summary: The forward plan — single home for outstanding work, deferred items, and
  the idea backlog. Routine done-work lives in `git log`; durable design lives in
  the topic-triggered reference docs under `docs/reference/`.
---

# Roadmap

The forward plan: actionable outstanding work, deferred-but-tracked items, and the idea backlog. **This is the single home for "what's next."** Items leave this file when done (folded into git log) or when explicitly killed.

## Outstanding (actionable)

- **Aurora migration — workstation-as-compute / aurora-as-family-vault.** Reorganises hosts to let workstation sleep when no GPU/transcode/bulk-storage workload is active and to give irreplaceable media a 3-copy replication posture. Full delta table, phase ordering, validation gates, and reversibility ladder in `docs/plans/2026-06-11-aurora-migration.md`. **Progress (2026-06-16):** P1–P15 ✓ landed (foundation + aurora bootstrap + data move + service-state migration + entry-plane flip + nightly btrbk replication aurora → workstation MP510 live since 2877267). P18 (s2idle resume hang) fixed b77b030; P19 ✓ landed end-to-end (pi `wakeonlan` sender 3674d89 + operator-verified magic-packet test 2026-06-16); P20 partially landed (PipeWire idle inhibit + hibernate setup + hypridle removal — manual triggers only). **Outstanding:** P20 hypridle re-enable (gated on operator verifying suspend works post-reboot). P16 pavilion tertiary replica future-work; P17 Hetzner explicitly rejected per ADR-0002.

- **Sunshine remote-desktop pairing.** Deployed (`modules/machines/desktop/sunshine.nix`); NVENC builds confirmed (`h264/hevc/av1_nvenc`). Outstanding: one-time Moonlight pairing.

  Pairing steps:

  1. **Clear stray instance** — `sunshine` user unit binds `graphical-session.target`, only autostarts on *fresh* Hyprland login (lock/unlock won't trigger). If a manually-started copy holds the ports: `kill` it or reboot so systemd owns it
  2. **MacBook side** — `brew install --cask moonlight`
  3. **Pair** — browse `https://workstation:47990` over tailnet, set admin creds, PIN-pair, launch "Desktop"
  4. **Verify** video + audio

  **Fallback** if NVIDIA KMS capture black-screens: `capSysAdmin = false` (wlr capture — Hyprland is wlroots-based) + rebuild.

  Design + plan: `docs/specs/2026-05-22-sunshine-remote-host-design.md`, `docs/plans/2026-05-22-sunshine-remote-host.md`.

- **MemoryHigh caps on heavy services** — process-exporter now publishes `namedprocess_namegroup_memory_bytes{memtype="resident",groupname=…,host=…}` to pi VM for all three workhorse hosts (workstation, pavilion, aurora). Wait ≥7 days of data, identify the slowest-growing services per host, cap each via `systemd.services.<n>.serviceConfig.MemoryHigh = "…G"`. Premature to cap blindly. Sample query: `topk(10, max_over_time(namedprocess_namegroup_memory_bytes{memtype="resident"}[7d]) - min_over_time(namedprocess_namegroup_memory_bytes{memtype="resident"}[7d])) / 1024 / 1024`. Special interest: aurora `gunicorn` (immich-ml — PyTorch, known leak shape).

## Deferred (tracked, not currently worked)

- **Mac is on x86_64-darwin EOL clock.** Confirmed 2026-06-15: **26.05 is the last nixpkgs stable supporting x86_64-darwin** (26.11 drops it). Determinate installer v3.12.2 was the last with x86_64-darwin (v3.12.3 dropped Intel). The Mac is currently pinned to 26.05 and works; "stay pinned indefinitely" is a valid stance until something else forces movement.

  | Layer | Status |
  |---|---|
  | HM config | `homeConfigurations.macbook` in `flake.nix`; content `modules/machines/macbook/home.nix` |
  | Switch cmd | `nix run home-manager/master -- switch --flake ~/Documents/nix-migration#macbook` |
  | Nix installer | Pin Determinate v3.12.2 OR upstream nix |
  | Nixpkgs lifeline | 26.05 (pinned indefinitely) |
  | Already adapted | `nix shell` over `home.packages` for heavy compiles (Hydra cache thin); ghostty + utm stay on brew |

  **Forcing functions to revisit:** a package the operator needs on Mac requires nixpkgs > 26.05; nixpkgs security advisories the operator wants for Mac specifically; the Intel Mac itself fails / gets replaced.

- **Remaining stabilisation (personal apps).** Phases 1-3 + 6-prep landed 2026-05-08 (CI + Renovate on all 4 app repos; zod validation on drinks-api; finnbydel → Astro + Hono; stateful apps → Drizzle + bun:sqlite; @sentry SDKs wired, no-op without DSN). Remaining: phase 4 (static sites → Cloudflare Pages, removes 3 attack surfaces from workstation), phase 5 (microvm.nix for drinks + finnbydel, kernel-level isolation for stateful apps that stay on workstation). Sentry activation when operator provisions projects: add 6 sops secrets `sentry-dsn-{heim,drinks-app,drinks-server,filmder,finnbydel-app,finnbydel-server}` to `secrets/apps.yaml`; update each module's environment block.

- **Remaining SSO candidates.** Second batch landed (Immich + Beszel native OIDC, Komga + calibre-web forward-auth). Still on the table:
  - **Native OIDC:** Komga could move from forward-auth to per-user OIDC if family members start wanting separate read-history; Spring Security OAuth2 config is verbose but doable.
  - **Skip / problematic:** Jellyfin (mobile/TV clients bypass cookie-based forward-auth; native SSO plugin has sharp historical edges). Radicale CalDAV clients can't follow forward-auth redirects, must stay on htpasswd. Glance/Gatus are intentionally public. Syncthing is single-admin. ntfy push API path exemption ends up too permissive to be worth gating the web UI alone.

- **Lower-priority appliance candidates.** Glance + Radicale moved to aurora at P11 (family-vault posture). The original motivation was "failure independence from workstation"; that's now achieved on the aurora→pi failure-domain axis. A *further* split to pi (independence from aurora too) is theoretical — aurora is meant to be always-on family-vault, so aurora outages are the rare path. Reopen only if aurora's failure profile turns out worse than projected.

## Promotion register (from `docs/invariants.md`)

`[prose: unchecked]` claims worth mechanizing — detail in `docs/invariants.md § promotion work-list`:

| Check | Promotes to | Catches |
|---|---|---|
| ~~`disko-uses-by-id`~~ | ✓ `[law: lint.diskoUsesById]` (landed 2026-06-16, nori.lint TOML registry) | `/dev/nvme[0-9]` or `/dev/sda[0-9]?` leakage (NVMe enum drift wipes wrong disk) |
| ~~`function-named-subdomains`~~ | ✓ `[law: lint.functionNamedSubdomains]` (landed 2026-06-16) | service-name leakage in `nori.lanRoutes` |
| ~~`audience-enforces-auth`~~ | ✓ `[structural: module assertion]` (landed 2026-06-21) | `audience="family"` without `oidc` / `forwardAuth` / explicit `noAuthReason` |
| ~~`infra-concerns-have-tests`~~ | ✓ `[law: infra-concerns-have-tests]` (landed 2026-06-21) | every `modules/infra/<X>/` with Reader-shaped `options.nori.*` has matching `test-*` recipe (mapping in `flake.nix § checks.infra-concerns-have-tests`) |
| `workhorse-vs-appliance-placement` | `[law]` — module assertion (eval-time, not grep) | service placement matches host role |
| ~~`systemd-execstart-resolves`~~ | ✗ REJECTED 2026-06-21 (zero catch rate on this codebase — every ExecStart already `${pkgs.foo}/bin/baz`; nix eval validates. See `docs/plans/2026-06-21-improve-audit.md § #4`) | — |

## Idea backlog (no commitment)

- **UPS for workstation.** Single PSU is a non-goal for HA, but mid-write power loss on USB-attached IronWolf is a real recovery scenario. Cheap (~1500–3000 NOK for 600VA) insurance.
- **IronWolf Pro from USB to internal SATA.** When SATA capacity becomes available (PCIe HBA). USB enclosures have their own failure mode at the controller level.
- **`common-cpu-amd-pstate`** module on workstation hardware.
- **NVIDIA Wayland edge cases** (multi-monitor VRR, suspend/resume nuances). Not blocking; document fixes in `hardware.nix` as encountered.
- **CUDA/Ollama drift.** Ollama bundles its own CUDA libs; verify at install and pin nixpkgs version if it doesn't.
- **Home automation on the Pi.** No concrete use case currently.

## Architectural debt (named compromises with a known correct shape)

- **Suspend-then-hibernate ladder on NVIDIA.** The conceptually-right power-savings ladder is idle → s2idle suspend → hibernate. Systemd's `suspend-then-hibernate` target hangs on NVIDIA systems per [systemd#27559](https://github.com/systemd/systemd/issues/27559) (closed-source-tainted-kernel; effectively won't-fix upstream because of how `freeze_thaw_user_slice()` interacts with NVIDIA's ACPI cooperation). Affects both the closed driver AND the open Blackwell module the workstation runs. Individual `systemctl hibernate` typically works; it's the combined ladder that hangs. **Trigger to revisit:** when systemd #27559 is resolved upstream OR when the workstation moves off NVIDIA. Until then, the workstation pattern stays: PipeWire-aware idle inhibit (landed 2026-06-15) for ambient sound-aware "don't sleep on me", manual `super+P` lock-then-suspend after the VRAM-preserve kernel param fix (landed 2026-06-15), `systemctl hibernate` (manual, when used) for session persistence, full power-off for max savings.

- **Noctalia v5 evaluation.** [Noctalia](https://github.com/noctalia-dev/noctalia) is a Quickshell-based (Qt6/QML) all-in-one Wayland desktop shell — bar + launcher + notifications + lock screen + idle behavior + OSDs + dock + wallpapers + multi-monitor. Would consolidate the workstation's current set (waybar + fuzzel + mako + hyprlock + hyprsunset, plus the just-landed wayland-pipewire-idle-inhibit) into one Qt-based shell with shared theme. **Cost of switching:** v5 is in alpha with breaking config/behaviour changes between releases; replacing a working stack of mature individual tools with one alpha shell trades known-good for active-churn. Lock-in risk: Quickshell + QML config style is meaningfully different from the current declarative-NixOS-modules pattern. **Trigger to revisit:** v5 reaches stable, OR the operator wants a coherent visual identity across surfaces and can absorb the churn for it. Today's status quo (waybar + mako + fuzzel + hyprlock + PipeWire idle inhibit) all-NixOS-declarative, all-stable.

- **Cross-host maintenance coordination for Gatus (G3).** Each Gatus instance has a 60s warmup via timer-driven activation (`gatus.timer` with `OnBootSec=60s` + `OnUnitInactiveSec=60s`, landed 2026-06-15 95dae3d in `modules/infra/observability/gatus.nix` after the earlier `ExecStartPre = sleep 60` approach was found to gate the boot critical path) — local probes don't alert on services that are still restarting after a `just rebuild`. But *another* host's Gatus probing the rebuilding one still fires (e.g. workstation's Gatus probing pi while pi rebuilds — once workstation grows its own instance). The correct shape: a per-host maintenance flag readable across hosts (HTTP endpoint or shared file) that every Gatus consults before alerting. Either a Gatus extension/fork that supports flag-based silencing, or a thin sidecar that mutates Gatus's alerting provider config at rebuild start/stop. **Trigger to revisit:** when a second Gatus instance lands on the homelab, or when cross-host probe flapping during rebuilds becomes annoying enough to outweigh the build cost.

- **Network-layer DNS/egress policy.** The correct layer for "force all LAN egress through Blocky and block public-resolver fall-throughs" is a real router (OPNsense/OpenWRT/pfSense) behind a bridge-mode modem, with nftables PREROUTING REDIRECT on :53 and a DoH-IP blocklist on the WAN-facing side. Today the Genexis ISP modem doesn't bridge-mode and a real router isn't budgeted, so the same policy is enforced one layer lower at `modules/infra/tailnet-appliance.nix` (pi-as-tailnet-exit-node DNAT). Limits documented in that file's header: only catches devices routing through pi, can't help LAN-only hardcoded-DNS devices, and DoH egress to non-listed IPs slips through. When a real router lands, this effect goes away; the same `nori.tailnet.appliances` registry drives the router's nftables generator instead. **Trigger to revisit:** ISP allowing Genexis bridge mode *or* a competent router (~$200) enters the budget.

