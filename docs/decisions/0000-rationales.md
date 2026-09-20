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
| **Btrfs everywhere on Linux** | ext4 root | Same mental model across roots and media; `@home` + `@var-lib` snapshots provide service-recovery beyond NixOS generations. CoW database gotcha addressed via `chattr +C` / `nodatacow`, separately from backup-consistency (logical dumps). | Subvolume layout in `infra/workstation/disko*.nix`; `nori.fs` tier in `infra/common/nixos/storage/default.nix` |
| **No ZFS** | ZFS root | Single-drive scale doesn't activate ZFS's main wins. Out-of-tree driver constrains kernel versions, conflicts with bleeding-edge Blackwell driver needs. | Absence; no zfs in `boot.supportedFilesystems` |
| **Default-deny network exposure** | Default-allow with exclusions | Default-allow is a maintenance treadmill that grows with every new service. | `networking.firewall` baseline plus manifest endpoints whose `exposeOnTailnet` default is false |
| **Default-deny filesystem access for service modules** | Trust upstream module hardening | Upstream NixOS modules already harden some surfaces (`ProcSubset=pid`, `ProtectKernelTunables`) but leave the mount namespace wide open. A compromised service shouldn't browse `/home` looking for keys. | `every-service-has-fs-hardening` flake check; `nori.harden.<unit>` in `infra/common/nixos/service-hardening.nix` |
| **Subvolumes split by value tier, not directory hierarchy** | Subvolumes by topic | Subvolumes are the unit of snapshot/backup policy. Same policy → same subvolume; different policy → different subvolume. | Subvolume table in `docs/reference/storage.md` and `infra/common/nixos/storage/default.nix` |
| **Disko at install, not deferred** | Manual partition + retrofit | First install is the right time. Deferring guarantees doing the work twice. | `infra/<host>/disko*.nix` applied at first boot |
| **Pi as appliance** | Pi as "small server" | Pi survives workstation outage and runs observability, alerting, DNS, and Tailscale plumbing. Pi backups target workstation storage because the FIT flash must not receive daily repository writes. | `inventory/hosts.nix` assigns Pi the appliance role; backup paths are in `docs/reference/storage.md` |
| **restic over btrbk send/receive for transport** | btrfs-native send/receive | Filesystem-agnostic — any restic target (OneTouch ext4, mp510 btrfs, future remote SFTP) works without filesystem coordination; single mental model whether the destination is btrfs or not. | `services.restic.backups.*` (transport); `services.btrbk.*` (local snapshot only) |
| **Self-hosted Authelia OIDC over Cloudflare Access** (reversed 2026-05) | Cloudflare Access | The original Phase-5 call was Cloudflare Access. It became irrelevant when public traffic moved to Cloudflare edge, while family-facing homelab services still needed per-user identity. | OIDC clients derive from `services/*/manifest.nix` through `inventory/default.nix`; forward-auth covers applications without native OIDC |
| **Backup-correctness via three documented patterns A/B/C** | Trust restic snapshots of running services | Filesystem snapshot of a live database is roulette. Logical dump before backup is the discipline; the patterns document which kind of dump for which kind of service. | Pattern table in `docs/reference/services.md` § Backup-correctness patterns; live impls in `services/restic-backup/nixos.nix` |
| **Hyprland over GNOME/KDE** | GNOME Shell | Declarative config matches the rest of the system. Tiling matches keyboard-heavy terminal use. | `profiles/desktop/nixos/hyprland.nix`; Hyprland 0.55+ Lua config |
| **`nixos-26.05` stable channel** (since 2026-06-03; previously unstable) | Stay on unstable; or 25.11 | Stable 26.05 ships NVIDIA driver 580+ for Blackwell support (the original reason for being on unstable). Cut over deliberately, not on every `nix flake update`. Downgrading pin direction strands persistent state in newer formats. | `flake.nix` `nixpkgs.url`; `Mnemopi recall: gotcha-nixpkgs-downgrade-strands-state` |
| **Tailnet IS the auth perimeter; Authelia only for per-user identity** | Authelia on every internal route | Device trust already exists before an HTTP request reaches an operator service. Repeating that gate makes Authelia load-bearing without adding identity value. | Endpoint `audience` and authentication declarations in workload manifests; compiler invariants in `inventory/default.nix` |
| **Function-named subdomains, not branded** | `gatus.nori.lan`, `jellyfin.nori.lan` | Functions survive product replacements. | Endpoint names such as `uptime`, `media`, `alert`, and `home` in workload manifests |
| **Single user `nori` + per-service auth for family** | Multi-user OS | Multi-user OS isolation isn't the goal; per-service identity propagation is. The hardware is one operator's daily-driver workstation. | One Linux user; family members get per-service accounts. Tailscale enrollment is required only for internal routes; ADR-0006 media routes use native accounts over public HTTPS. |
| **Native NixOS modules first, containers as fallback** | Docker-compose orchestration | Containers add an orchestration layer NixOS doesn't need at this scale. Native modules compose with `nori.<X>` effects directly; container wrappers fight the abstraction. | `services/*/nixos.nix` use native `services.<svc>` modules where available; no `virtualisation.oci-containers` |
| **Distributed build via aarch64-binfmt on workstation, not cross-compilation** | Cross-compile in nixpkgs | Cross-compilation in nixpkgs is rougher than people expect for full system closures. binfmt-emulated native build on a fast x86 host is the pragmatic answer. | `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` on workstation; `nh os switch --target-host pi --build-host workstation` |
| **No high availability** | Active-passive failover | Single-PSU residential lab; HA isn't a goal. RTO ladder makes the tradeoff explicit. | `docs/reference/recovery.md` RTO table; no HA mechanisms |
| **Explicit family-media internet allowlist** (reversed 2026-07) | Require every family device to join Tailscale; publish the wildcard; Tailscale Funnel / cloudflared for all traffic | Jellyfin, Seerr, and Navidrome need low-friction native clients and per-user app accounts. WAN 443 may reach pi, but route-level address matchers keep every non-allowlisted hostname internal and a catch-all rejects unknown hosts. Direct forwarding avoids Cloudflare's self-serve media-delivery restrictions; route-derived DNS-only DDNS keeps exact records current. | ADR-0006; `nori.lanRoutes.<n>.reachability`; Caddy + Cloudflare-DDNS eval tests |
| **Runtime introspection tests** (added 2026-06-07) | Flake checks alone | Flake checks cover declaration ↔ declaration consistency at build time but can't catch declaration ↔ runtime desync (e.g. backup unit exists but snapshot is stale, route declared but Caddy didn't pick it up). `just test-*` recipes query live registries to assert the runtime matches the declaration. | `Justfile` recipes `test-{hypr,backups,routes,observability,replicas}`; framework in `docs/reference/runtime-tests.md`; the `[runtime-introspection]` enforcement tier in `docs/invariants.md` |
| **FLEET/AGENT alerts on the self-hosted pi hub; CRITICAL INFRA stays on ntfy.sh** (2026-07-23) | Route everything through one ntfy instance (all-local or all-public) | Agent-fleet volume was tripping ntfy.sh's public rate limit (429s) and sharing that quota with alerts that most need to get through. But infra alerts (backup/service failures) must survive the homelab itself being down — pointing them at a service the homelab hosts would be self-defeating. The split is per-channel (`nori.alerts.channels.<n>.baseUrl` + `authTokenSecret`), not a producer-side convention. | `nori.alerts.channels.agents` → pi hub in `infra/workstation/default.nix`; `nori.alerts.channels.infra` → ntfy.sh in `services/ntfy/nixos/notify.nix`; split proven end-to-end by `tests/e2e-alerts-channel-auth.nix` |

## When to add a row

A row earns its keep when the decision **changed direction at least once** or **has a tempting-but-wrong alternative someone will propose again**. Don't list every choice — the test is "would a fresh agent re-litigate this in 6 months without the row?"

If the decision is large enough that a fresh reader would want the full Context / Decision / Consequences narrative, skip this register and write a full ADR at `docs/decisions/NNNN-*.md` instead. Per the README, the threshold is roughly: *would coordinated multi-module changes be required to reverse it?*
