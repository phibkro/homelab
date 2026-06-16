---
summary: The forward plan — single home for outstanding work, deferred items, and
  the idea backlog. Routine done-work lives in `git log`; durable design lives in
  the tier-2 reference docs (TOPOLOGY/STORAGE/NETWORK/SERVICES/MODULES/…).
---

# Roadmap

The forward plan: actionable outstanding work, deferred-but-tracked items, and the idea backlog. **This is the single home for "what's next."** Items leave this file when done (folded into git log) or when explicitly killed.

## Outstanding (actionable)

- **Aurora migration — workstation-as-compute / aurora-as-family-vault.** Reorganises hosts to let workstation sleep when no GPU/transcode/bulk-storage workload is active and to give irreplaceable media a 3-copy replication posture. Full delta table, phase ordering, validation gates, and reversibility ladder in `docs/plans/2026-06-11-aurora-migration.md`. **Progress (2026-06-15):** P1–P14 ✓ landed (foundation + aurora bootstrap + data move + service-state migration + the entry-plane flip itself); P18 diagnosed + fixed (b77b030 — `nvidia.NVreg_PreserveVideoMemoryAllocations=1` on kernel cmdline; was the s2idle resume hang); P19 sender side landed (3674d89 — `wakeonlan` on pi for phone-side WoL); P20 partially landed (PipeWire idle inhibit 6f887e4 + hibernate setup 5de4cab + hypridle removal 45d1899 — sleep posture functional, manual triggers only). **Outstanding:** P15 (replication — sender + receiver modules drafted `04629a6` + `ba38187`, awaits operator ssh-key bootstrap), P19 magic-packet test gated on operator reboot, P20 hypridle re-enable (gated on operator verifying suspend works post-reboot). P16 pavilion tertiary replica future-work; P17 Hetzner explicitly rejected per ADR-0002.

- **Docs-shape review (post-aurora-migration).** Make filesystem depth encode tier (root = L0/L1, `docs/` = L2, `docs/<sub>/` = L3) so progressive-disclosure read-cost matches structural depth. Main pass at aurora-migration Phase 17, quick second pass at Phase 20. Decisions made + target shape + migration phasing captured in `docs/plans/2026-06-11-docs-shape-review.md` so the future-me starting Phase 17 inherits the design rather than re-deriving it.

- **Full documentation deep-scan (post-aurora-migration).** Today's session caught targeted drift in 9 memory entries + 3 repo docs while the rsync was running; the spot-checks covered the blast radius of today's commits but were not exhaustive. Once P10/P11/P12 settle, do a full pass across `docs/`, `.claude/skills/` (~35 gotcha skills), and the `~/.claude/projects/-srv-share-projects/memory/` set. Look for: stale paths (e.g. `modules/server` → `modules/services`), stale URLs (`*.nori.lan` examples that should be `*.${nori.domain}` post-ADR-0004), references to deleted/renamed artifacts (`@restic-local`, the `ironwolf` backup target name, the `caddy-local-ca.crt` file), historical narration in code-adjacent docs that violates the comment-hygiene principle from PR #10. `git log --since="2026-06-11"` is the changeset to verify against.

- **Sunshine remote-desktop pairing.** Deployed (`modules/desktop/sunshine.nix`); NVENC builds confirmed (`h264/hevc/av1_nvenc`). Outstanding: one-time Moonlight pairing.

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
  | HM config | `homeConfigurations.macbook` in `flake.nix`; content `machines/macbook/home.nix` |
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

- **Batch C: generated docs from live config.** Replace static "active services" + "host placement" + "snapshot policy" tables in `SERVICES.md` / `TOPOLOGY.md` / `STORAGE.md` with `nix eval`-driven output (`scripts/render-docs.sh` → `docs/auto/*.md`, gated by a `docs-fresh` flake check). Eliminates a class of doc drift entirely (executable docs don't decay). Roughly 1–2h to land.

## Promotion register (from INVARIANTS.md)

`[prose: unchecked]` claims worth mechanizing — detail in `INVARIANTS.md § promotion work-list`:

| Check | Promotes to | Catches |
|---|---|---|
| `disko-uses-by-id` | `[law]` — flake check, grep disko files | `/dev/nvme[0-9]` or `/dev/sda[0-9]?` leakage (NVMe enum drift wipes wrong disk) |
| `function-named-subdomains` | `[law]` — flake check, brand denylist | service-name leakage in `nori.lanRoutes` |
| `workhorse-vs-appliance-placement` | `[law]` — module assertion | service placement matches host role |
| `systemd-execstart-resolves` | `[law]` — flake check | ExecStart's first token resolves to closure path (incident 2026-06-03 class) |
| `effects-have-tests` *(added 2026-06-07)* | `[law]` — meta-check | every `modules/effects/<X>.nix` with Reader+Writer shape has matching `just test-<X>` recipe in `Justfile`. See `docs/reference/runtime-tests.md` |

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

- **Cross-host maintenance coordination for Gatus (G3).** Each Gatus instance has a 60s warmup via timer-driven activation (`gatus.timer` with `OnBootSec=60s` + `OnUnitInactiveSec=60s`, landed 2026-06-15 95dae3d in `modules/services/gatus.nix` after the earlier `ExecStartPre = sleep 60` approach was found to gate the boot critical path) — local probes don't alert on services that are still restarting after a `just rebuild`. But *another* host's Gatus probing the rebuilding one still fires (e.g. workstation's Gatus probing pi while pi rebuilds — once workstation grows its own instance). The correct shape: a per-host maintenance flag readable across hosts (HTTP endpoint or shared file) that every Gatus consults before alerting. Either a Gatus extension/fork that supports flag-based silencing, or a thin sidecar that mutates Gatus's alerting provider config at rebuild start/stop. **Trigger to revisit:** when a second Gatus instance lands on the homelab, or when cross-host probe flapping during rebuilds becomes annoying enough to outweigh the build cost.

- **Network-layer DNS/egress policy.** The correct layer for "force all LAN egress through Blocky and block public-resolver fall-throughs" is a real router (OPNsense/OpenWRT/pfSense) behind a bridge-mode modem, with nftables PREROUTING REDIRECT on :53 and a DoH-IP blocklist on the WAN-facing side. Today the Genexis ISP modem doesn't bridge-mode and a real router isn't budgeted, so the same policy is enforced one layer lower at `modules/effects/tailnet-appliance.nix` (pi-as-tailnet-exit-node DNAT). Limits documented in that file's header: only catches devices routing through pi, can't help LAN-only hardcoded-DNS devices, and DoH egress to non-listed IPs slips through. When a real router lands, this effect goes away; the same `nori.tailnet.appliances` registry drives the router's nftables generator instead. **Trigger to revisit:** ISP allowing Genexis bridge mode *or* a competent router (~$200) enters the budget.

