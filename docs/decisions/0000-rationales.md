---
summary: Meta-ADR for small load-bearing decisions that don't warrant their own
  numbered ADR but still need a "why" home. One-row-per-decision register;
  lifted from the dissolved DESIGN.md (2026-06-03) and kept here so the rationales
  don't hide inside an architecture reference.
---

# ADR-0000: Small-decision rationales register

- Status: Accepted
- Date: 2026-06-03 (originated as `RATIONALES.md`); 2026-06-16 (relocated as ADR-0000)

## Context

Some load-bearing decisions are too small to warrant a full numbered ADR but still need a recorded "why" — otherwise a fresh agent re-litigates them every few months. The criteria for a full ADR (`docs/decisions/README.md`) gate is fairly high; below it sat a tier of choices that previously lived in `RATIONALES.md` at the top of `docs/`.

This file is the register for that tier. One row per decision: what was picked, what was rejected, why it stuck, where to verify it still holds.

## Decision

Small-but-load-bearing rationales live as a single-row entries in the table below. The register is part of `docs/decisions/` as ADR-0000 — the **meta-index for small decisions**. Hard-to-revisit choices large enough to need full Context / Decision / Consequences sections become their own numbered ADR (0001+).

When a row's decision changes, **update the row** (this is not append-only like a full ADR). When implementation drifts, fix here or in code — never both.

## Consequences

- Every row is a candidate to be **promoted to a full ADR** if the decision becomes load-bearing enough that a fresh reader needs the full Context / Decision / Consequences narrative. Promotion is a structural-change-shaped move; capture in the new ADR's "Supersedes" line.
- Newer decisions that meet the full-ADR bar from the start skip this register entirely; they land directly as `NNNN-*.md`.
- The split is by **mechanism** (when/how recorded), not by **importance**. A small entry here can still be load-bearing.

## Rationales register

| Decision | Rejected alternative | Why it stuck | Evidence today |
|---|---|---|---|
| **Btrfs everywhere on Linux** | ext4 root | Same mental model across roots and media; `@home` + `@var-lib` snapshots provide service-recovery beyond NixOS generations. CoW database gotcha addressed via `chattr +C` / `nodatacow`, separately from backup-consistency (logical dumps). | Subvolume layout in `machines/workstation/disko*.nix`; `nori.fs` tier in `modules/effects/fs.nix` |
| **No ZFS** | ZFS root | Single-drive scale doesn't activate ZFS's main wins. Out-of-tree driver constrains kernel versions, conflicts with bleeding-edge Blackwell driver needs. | Absence; no zfs in `boot.supportedFilesystems` |
| **Default-deny network exposure** | Default-allow with exclusions | Default-allow is a maintenance treadmill that grows with every new service. | `networking.firewall` baseline + `nori.lanRoutes.<n>.exposeOnTailnet = false` default |
| **Default-deny filesystem access for service modules** | Trust upstream module hardening | Upstream NixOS modules already harden some surfaces (`ProcSubset=pid`, `ProtectKernelTunables`) but leave the mount namespace wide open. A compromised service shouldn't browse `/home` looking for keys. | `every-service-has-fs-hardening` flake check; `nori.harden.<unit>` in `modules/effects/harden.nix` |
| **Subvolumes split by value tier, not directory hierarchy** | Subvolumes by topic | Subvolumes are the unit of snapshot/backup policy. Same policy → same subvolume; different policy → different subvolume. | Subvolume table in `docs/reference/storage.md` and `modules/effects/fs.nix` |
| **Disko at install, not deferred** | Manual partition + retrofit | First install is the right time. Deferring guarantees doing the work twice. | `machines/<host>/disko*.nix` applied at first boot |
| **Pi as appliance** | Pi as "small server" | Pi survives workstation outage and runs observability + alerting + DNS + Tailscale plumbing. The "Pi-as-backup-target" plan deferred until a real disk replaces the FIT flash (anti-write posture rules out daily restic to flash). Today's backup repos live on workstation USB drives (OneTouch + mp510). | Pi role in `nori.hosts.pi.role = "appliance"`; backup paths in `docs/reference/storage.md` |
| **Two adblock-aware DNS resolvers (Pi + workstation)** | Pi-only with router DHCP fallback | DHCP-distributed secondaries don't fail over fast; resolver timeouts mean Pi-down = seconds of broken DNS. Both Blocky instances at trivial resource cost. | `services.blocky` enabled on both hosts; Tailscale global-nameserver push points at Pi |
| **Blocky over AdGuard Home** | AdGuard Home | Declarative YAML config maps cleanly to `services.blocky.settings`; no web-UI state to drift from declared config. | `modules/services/blocky.nix` |
| **restic over btrbk send/receive for transport** | btrfs-native send/receive | Filesystem-agnostic — any restic target (OneTouch ext4, mp510 btrfs, future remote SFTP) works without filesystem coordination; single mental model whether the destination is btrfs or not. | `services.restic.backups.*` (transport); `services.btrbk.*` (local snapshot only) |
| **Self-hosted Authelia OIDC over Cloudflare Access** (reversed 2026-05) | Cloudflare Access | The original Phase-5 call was Cloudflare Access (free, no self-hosted infra). Reversed once the public surface moved off workstation to Cloudflare edge (Pages + Workers, 2026-05-08): with no homelab-served public traffic Access had nothing to gate, while family-facing tailnet services (Jellyfin, Immich, Vaultwarden) needed per-user identity propagated *into the app* — which Access at the edge can't do for tailnet-only routes. | Authelia auto-generated from `nori.lanRoutes.<n>.oidc`; forward-auth covers apps without native OIDC (Komga, calibre-web) |
| **Backup-correctness via three documented patterns A/B/C** | Trust restic snapshots of running services | Filesystem snapshot of a live database is roulette. Logical dump before backup is the discipline; the patterns document which kind of dump for which kind of service. | Pattern table in `docs/reference/services.md` § Backup-correctness patterns; live impls in `modules/services/backup/restic.nix` |
| **Hyprland over GNOME/KDE** | GNOME Shell | Declarative config matches the rest of the system. Tiling matches keyboard-heavy terminal use. | `modules/desktop/hyprland.nix`; Hyprland 0.55+ Lua config |
| **`nixos-26.05` stable channel** (since 2026-06-03; previously unstable) | Stay on unstable; or 25.11 | Stable 26.05 ships NVIDIA driver 580+ for Blackwell support (the original reason for being on unstable). Cut over deliberately, not on every `nix flake update`. Downgrading pin direction strands persistent state in newer formats. | `flake.nix` `nixpkgs.url`; `.claude/skills/gotcha-nixpkgs-downgrade-strands-state/` |
| **Tailnet IS the auth perimeter; Authelia only for per-user identity** | Authelia on every internal route | Device-level trust from Tailscale is already established before any HTTP request lands; layering Authelia on top of operator-only services duplicates the network-perimeter guarantee and makes Authelia uptime load-bearing for operator workflows. | `audience` enum on `nori.lanRoutes` (`operator` skips Authelia; `family` gets OIDC; `public` is intentionally open) |
| **Function-named subdomains, not branded** | `gatus.nori.lan`, `jellyfin.nori.lan` | The brand changes (Uptime Kuma → Gatus); the function doesn't. URLs survive tool swaps. | Naming in `nori.lanRoutes.<n>`: `status` `media` `chat` `alert` `home` |
| **Single user `nori` + per-service auth for family** | Multi-user OS | Multi-user OS isolation isn't the goal; per-service identity propagation is. The hardware is one operator's daily-driver workstation. | One Linux user; family members get per-service accounts in Jellyfin / Immich / Open WebUI / Vaultwarden + Tailscale invites |
| **Native NixOS modules first, containers as fallback** | Docker-compose orchestration | Containers add an orchestration layer NixOS doesn't need at this scale. Native modules compose with `nori.<X>` effects directly; container wrappers fight the abstraction. | `modules/services/*.nix` all use `services.<svc>` modules; no `virtualisation.oci-containers` |
| **Distributed build via aarch64-binfmt on workstation, not cross-compilation** | Cross-compile in nixpkgs | Cross-compilation in nixpkgs is rougher than people expect for full system closures. binfmt-emulated native build on a fast x86 host is the pragmatic answer. | `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` on workstation; `nh os switch --target-host pi --build-host workstation` |
| **No high availability** | Active-passive failover | Single-PSU residential lab; HA isn't a goal. RTO ladder makes the tradeoff explicit. | `docs/reference/recovery.md` RTO table; no HA mechanisms |
| **No public internet hosting from the homelab** | Tailscale Funnel / cloudflared on workstation | Personal apps that need public surface live at the Cloudflare edge (Pages + Workers). If a future service ever needs to land public traffic on workstation, Tailscale Funnel is the prototyped path. | `nori.lanRoutes` all `audience != "public-internet"`; Funnel reference preserved in memory |
| **Runtime introspection tests** (added 2026-06-07) | Flake checks alone | Flake checks cover declaration ↔ declaration consistency at build time but can't catch declaration ↔ runtime desync (e.g. backup unit exists but snapshot is stale, route declared but Caddy didn't pick it up). `just test-*` recipes query live registries to assert the runtime matches the declaration. | `Justfile` recipes `test-{hypr,backups,routes,observability,replicas}`; framework in `docs/reference/runtime-tests.md`; the `[runtime-introspection]` enforcement tier in `docs/invariants.md` |

## When to add a row

A row earns its keep when the decision **changed direction at least once** or **has a tempting-but-wrong alternative someone will propose again**. Don't list every choice — the test is "would a fresh agent re-litigate this in 6 months without the row?"

If the decision is large enough that a fresh reader would want the full Context / Decision / Consequences narrative, skip this register and write a full ADR at `docs/decisions/NNNN-*.md` instead. Per the README, the threshold is roughly: *would coordinated multi-module changes be required to reverse it?*
