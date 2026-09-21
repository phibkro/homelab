---
summary: The forward plan — single home for outstanding work, deferred items, and
  the idea backlog. Routine done-work lives in `git log`; durable design lives in
  the topic-triggered reference docs under `docs/reference/`.
---

# Roadmap

The forward plan: actionable outstanding work, deferred-but-tracked items, and the idea backlog. **This is the single home for "what's next."** Items leave this file when done (folded into git log) or when explicitly killed.

## Outstanding (actionable)


- **Finish ADR-0006 router cutover and external acceptance.** Route-derived
  DNS-only A records, Pi DDNS reconciliation, and Caddy's exact-host/source
  boundary are ready declaratively. The public status Worker is deployed.
  Its scheduled probes report `outage` because WAN TCP 443 is not forwarded.
  [Production acceptance evidence](archive/reports/2026-09-21-public-status-acceptance.md)
  records the observed boundary. Forward WAN TCP 443 to
  `192.168.1.225:443`, never port 80. Then run ADR-0006's cellular-data checks
  for all three family logins, known-internal hosts, and random-host 404s.
  Confirm that the router preserves the real client source IP. Wait for an
  `operational` scheduled status result. Finally, stop and restart Navidrome
  and record an `operational → outage → operational` probe transition.

- **Finish the Pi appliance migration.** Pi owns the failure-independent
  network appliance plane: DNS, HTTPS entry, identity, Glance, monitoring,
  alerting, Tailscale routing, and appliance backups. `inventory/hosts.nix`
  remains the topology authority while `infra/pi/` provisions the
  Debian/Ansible/Podman realization. Complete the physical reboot and off-LAN
  gates in `docs/specs/ansible-pi-plan-b.md`. Ansible is now the sole live
  deployment owner; the verified NixOS image remains only as an offline
  rollback artifact. The September 19 acceptance pass established the Pi
  identity, backup transport, eight fresh snapshots, eight metadata checks, and
  one byte-for-byte Pi-hole configuration restore. Remaining gates are physical
  reboot, off-LAN behavior, application/database recovery, user-data/media
  restore coverage, and full data-block integrity. Evidence:
  `docs/archive/reports/2026-09-19-backup-evidence.md`. Aurora and Pavilion are
  retired.

- **Build an inventory-derived operator view.** Generate a read-only service
  view from the inventory and runtime probes. Show each service's host, route,
  authentication method, health, backup freshness, deployment owner, and
  recovery reference. Do not add another service registry or add mutations to
  the first version.

- **Build the authenticated family onboarding portal.** Reuse the access-tiered
  route projection for capability filtering, registration guidance, Tailscale
  setup, and generated walkthroughs. Keep its authentication and release
  lifecycle separate from the public status Worker. Start after the public
  status component contract passes production acceptance.

- **Refine outcome-based monitoring.** Monitor DNS, authentication, external
  HTTPS, application health, backup freshness, restore-evidence age, disk
  headroom, and certificate lifetime. Remove duplicate alerts for the same
  failure. Add maintenance suppression only after planned work causes proven
  alert noise.

- **Sunshine remote-desktop pairing.** Deployed (`services/sunshine/nixos.nix`); NVENC builds confirmed (`h264/hevc/av1_nvenc`). Outstanding: one-time Moonlight pairing.

  Pairing steps:

  1. **Clear stray instance** — `sunshine` user unit binds `graphical-session.target`, only autostarts on *fresh* Hyprland login (lock/unlock won't trigger). If a manually-started copy holds the ports: `kill` it or reboot so systemd owns it
  2. **MacBook side** — `brew install --cask moonlight`
  3. **Pair** — browse `https://workstation:47990` over tailnet, set admin creds, PIN-pair, launch "Desktop"
  4. **Verify** video + audio

  **Fallback** if NVIDIA KMS capture black-screens: `capSysAdmin = false` (wlr capture — Hyprland is wlroots-based) + rebuild.

  Design + plan: `docs/specs/2026-05-22-sunshine-remote-host-design.md`, `docs/archive/plans/2026-05-22-sunshine-remote-host.md`.

- **MemoryHigh caps on heavy services** — process-exporter publishes `namedprocess_namegroup_memory_bytes{memtype="resident",groupname=…,host=…}` for the converged workstation. Wait ≥7 days after deployment, identify the slowest-growing services, and cap each via `systemd.services.<n>.serviceConfig.MemoryHigh = "…G"`. Premature to cap blindly. Sample query: `topk(10, max_over_time(namedprocess_namegroup_memory_bytes{memtype="resident"}[7d]) - min_over_time(namedprocess_namegroup_memory_bytes{memtype="resident"}[7d])) / 1024 / 1024`. Special interest: `immich-machine-learning` (PyTorch).

- **Media acquisition — papers + manga built, undeployed.** Both now evaluate on workstation and remain operator-gated behind `just rebuild`.
  - **Papers** (acquisition-first): Paperless-ngx archive + OA-first fetcher CLI (DOI/arXiv/title → arXiv→Unpaywall→OpenAlex → Paperless consume dir; gray-zone off). Spec: `docs/specs/2026-06-23-papers-acquisition.md`. Follow-ups: search PWA (P2), reading-list sync (P3), verify anonymous lossless tier; own-repo graduation if it grows.
  - **Manga**: Suwayomi-Server is co-located with Komga on workstation and writes `library/manga` directly.
  - **Comics (Mylar3)** remains deferred because it would be the repository's first OCI-container service; the former cross-host storage blocker no longer applies.
  - **Books → Readarr** remains an unstarted \*arr addition.
  - ⚠ **Process note:** the two build ICs were dispatched with `isolation: "worktree"` but landed on `main` sharing one tree (isolation didn't take) — caught before commit, untangled by hand. Verify worktree isolation actually engaged before parallel same-repo dispatches.

## Deferred (tracked, not currently worked)

- **~~Mac is on x86_64-darwin EOL clock.~~ RESOLVED 2026-07-26 — retired.** nixpkgs 26.11 dropped `x86_64-darwin` before a decision was made, which took `nix flake check` red on main. The Mac had already fallen out of use, so the configuration was removed rather than migrated or pinned. See ADR-0009 (supersedes ADR-0006). If a Mac returns it will be Apple Silicon and a fresh inventory entry.

- **Remaining stabilisation (personal apps).** Phases 1-3 + 6-prep landed 2026-05-08 (CI + Renovate on all 4 app repos; zod validation on drinks-api; finnbydel → Astro + Hono; stateful apps → Drizzle + bun:sqlite; @sentry SDKs wired, no-op without DSN). Remaining: phase 4 (static sites → Cloudflare Pages, removes 3 attack surfaces from workstation), phase 5 (microvm.nix for drinks + finnbydel, kernel-level isolation for stateful apps that stay on workstation). Sentry activation when operator provisions projects: add 6 sops secrets `sentry-dsn-{heim,drinks-app,drinks-server,filmder,finnbydel-app,finnbydel-server}` to `secrets/apps.yaml`; update each module's environment block.

- **Remaining SSO candidates.** Second batch landed (Immich + Beszel native OIDC, Komga + calibre-web forward-auth). Still on the table:
  - **Native OIDC:** Komga could move from forward-auth to per-user OIDC if family members start wanting separate read-history; Spring Security OAuth2 config is verbose but doable.
  - **Skip / problematic:** Jellyfin (mobile/TV clients bypass cookie-based forward-auth; native SSO plugin has sharp historical edges). Radicale CalDAV clients can't follow forward-auth redirects, must stay on htpasswd. Glance/Gatus are intentionally public. Syncthing is single-admin. ntfy push API path exemption ends up too permissive to be worth gating the web UI alone.

## Promotion register (from `docs/invariants.md`)

`[prose: unchecked]` claims worth mechanizing — detail in `docs/invariants.md § promotion work-list`:

| Check | Promotes to | Catches |
|---|---|---|
| ~~`disko-uses-by-id`~~ | ✓ `[law: lint.diskoUsesById]` (landed 2026-06-16, nori.lint TOML registry) | `/dev/nvme[0-9]` or `/dev/sda[0-9]?` leakage (NVMe enum drift wipes wrong disk) |
| ~~`function-named-subdomains`~~ | ✓ `[law: lint.functionNamedSubdomains]` (landed 2026-06-16) | service-name leakage in `nori.lanRoutes` |
| ~~`audience-enforces-auth`~~ | ✓ `[structural: module assertion]` (landed 2026-06-21) | `audience="family"` without `oidc` / `forwardAuth` / explicit `noAuthReason` |
| ~~`infra-concerns-have-tests`~~ | ✓ `[law: infra-concerns-have-tests]` (landed 2026-06-21) | every shared `options.nori.*` schema is discovered and explicitly registered; runtime-observable effects name a matching `test-*` recipe, while exact hardware/projection exceptions name their evaluation evidence |
| ~~`workhorse-vs-appliance-placement`~~ | ✓ `[law: eval-workload-role-placement]` (landed 2026-07-22; pure inventory assertion) | service placement matches the typed roles declared by its manifest |
| ~~`systemd-execstart-resolves`~~ | ✗ REJECTED 2026-06-21 (zero catch rate on this codebase — every ExecStart already `${pkgs.foo}/bin/baz`; nix eval validates. See `docs/archive/plans/2026-06-21-improve-audit.md § #4`) | — |

## Idea backlog (no commitment)

- **`common-cpu-amd-pstate`** module on workstation hardware.
- **NVIDIA Wayland edge cases** (multi-monitor VRR, suspend/resume nuances). Not blocking; document fixes in `hardware.nix` as encountered.
- **CUDA/Ollama drift.** Ollama bundles its own CUDA libs; verify at install and pin nixpkgs version if it doesn't.
- **Home automation on the Pi.** No concrete use case currently.

## Architectural debt (named compromises with a known correct shape)

- **Suspend-then-hibernate ladder on NVIDIA.** The conceptually-right power-savings ladder is idle → s2idle suspend → hibernate. Systemd's `suspend-then-hibernate` target hangs on NVIDIA systems per [systemd#27559](https://github.com/systemd/systemd/issues/27559) (closed-source-tainted-kernel; effectively won't-fix upstream because of how `freeze_thaw_user_slice()` interacts with NVIDIA's ACPI cooperation). Affects both the closed driver AND the open Blackwell module the workstation runs. Individual `systemctl hibernate` typically works; it's the combined ladder that hangs. **Trigger to revisit:** when systemd #27559 is resolved upstream OR when the workstation moves off NVIDIA. Until then, the workstation pattern stays: PipeWire-aware idle inhibit (landed 2026-06-15) for ambient sound-aware "don't sleep on me", manual `super+P` lock-then-suspend after the VRAM-preserve kernel param fix (landed 2026-06-15), `systemctl hibernate` (manual, when used) for session persistence, full power-off for max savings.

- **Noctalia v5 evaluation.** [Noctalia](https://github.com/noctalia-dev/noctalia) is a Quickshell-based (Qt6/QML) all-in-one Wayland desktop shell — launcher + notifications + lock screen + idle behavior + OSDs + dock + wallpapers + multi-monitor. Persona now owns the workstation wallpaper, launcher, media surface, native notifications, and OSDs; Noctalia would consolidate the remaining hyprlock + hyprsunset + wayland-pipewire-idle-inhibit concerns behind one shell. **Cost of switching:** v5 is in alpha with breaking config/behaviour changes between releases; replacing the pinned Persona integration and mature individual tools trades known behavior for active churn. **Trigger to revisit:** v5 reaches stable and materially replaces the remaining session daemons. Today's status quo is Persona Quickshell + fuzzel-backed rice palette + hyprlock + Hyprsunset + PipeWire idle inhibit, all wired declaratively through NixOS/Home Manager.

- **Maintenance suppression for Gatus (G3).** The Pi/workstation split means a
  planned workstation rebuild can create noisy backend alerts while the Pi and
  Gatus remain healthy. Add a maintenance flag only after observing that
  failure mode; do not suppress genuine appliance or WAN failures.

- **Network-layer DNS/egress policy.** The correct layer for "force all LAN
  egress through Blocky and block public-resolver fall-throughs" is a real
  router (OPNsense/OpenWRT/pfSense) behind a bridge-mode modem. Today the
  Genexis ISP modem does not bridge and a real router is not budgeted, so the
  policy lives one layer lower in `infra/pi/ansible/roles/firewall` and
  `services/tailscale/ansible`. It only catches devices routing through Pi, cannot help
  LAN-only hardcoded-DNS devices, and cannot block unlisted DoH endpoints.
  **Trigger to revisit:** ISP allowing Genexis bridge mode *or* a competent
  router (~$200) enters the budget.
