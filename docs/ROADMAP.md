---
summary: The forward plan — single home for outstanding work, deferred items, and
  the idea backlog. Routine done-work lives in `git log`; durable design lives in
  the tier-2 reference docs (TOPOLOGY/STORAGE/NETWORK/SERVICES/MODULES/…).
---

# Roadmap

The forward plan: actionable outstanding work, deferred-but-tracked items, and the idea backlog. **This is the single home for "what's next."** Items leave this file when done (folded into git log) or when explicitly killed.

## Outstanding (actionable)

- **Aurora migration — workstation-as-compute / aurora-as-family-vault.** Reorganises hosts to let workstation sleep when no GPU/transcode/bulk-storage workload is active and to give irreplaceable media a 3-copy replication posture. Full delta table, phase ordering, validation gates, and reversibility ladder in `docs/superpowers/plans/2026-06-11-aurora-migration.md`. **Progress (2026-06-11):** P1 (placement schema) + P1b (route lift + runsOn) + P2 (service-module sweep) + P3 (host opt-in) + P4 (nori.fs.samba) + P6 (aurora HDD format) + P13 (OneTouch SFTP target on aurora) landed — semantic equivalence proven per host. **ADR-0003 pivot:** HTTP entry plane (Caddy + Authelia + Blocky-authoritative) now lands on **pi** not aurora; aurora is pure family-data + service backends. P7/P8/P12 reworked in the plan. Data-move phases (P9+) still need operator hands.

- **Docs-shape review (post-aurora-migration).** Make filesystem depth encode tier (root = L0/L1, `docs/` = L2, `docs/<sub>/` = L3) so progressive-disclosure read-cost matches structural depth. Main pass at aurora-migration Phase 17, quick second pass at Phase 20. Decisions made + target shape + migration phasing captured in `docs/superpowers/plans/2026-06-11-docs-shape-review.md` so the future-me starting Phase 17 inherits the design rather than re-deriving it.

- **Full documentation deep-scan (post-aurora-migration).** Today's session caught targeted drift in 9 memory entries + 3 repo docs while the rsync was running; the spot-checks covered the blast radius of today's commits but were not exhaustive. Once P10/P11/P12 settle, do a full pass across `docs/`, `.claude/skills/` (~35 gotcha skills), and the `~/.claude/projects/-srv-share-projects/memory/` set. Look for: stale paths (e.g. `modules/server` → `modules/services`), stale URLs (`*.nori.lan` examples that should be `*.${nori.domain}` post-ADR-0004), references to deleted/renamed artifacts (`@restic-local`, the `ironwolf` backup target name, the `caddy-local-ca.crt` file), historical narration in code-adjacent docs that violates the comment-hygiene principle from PR #10. `git log --since="2026-06-11"` is the changeset to verify against.

- **Mac is on x86_64-darwin EOL clock.**

  | Layer | Status |
  |---|---|
  | HM config | `homeConfigurations.macbook` in `flake.nix`; content `machines/macbook/home.nix` |
  | Switch cmd | `nix run home-manager/master -- switch --flake ~/Documents/nix-migration#macbook` |
  | Nix installer | Determinate v3.12.2 (2025-11-05) — **last release with x86_64-darwin**; v3.12.3 dropped Intel. Pin v3.12.2 or use upstream for new installs |
  | Nixpkgs lifeline | 26.05 = **last release supporting x86_64-darwin** (eval warnings surface this) |
  | Already adapted | `nix shell` over `home.packages` for heavy compiles (Hydra cache thin); ghostty + utm stay on brew |

  **Decision needed** when next stable ships: pin Mac to 26.05 indefinitely / migrate Mac off Nix / replace hardware.

- **Jellyfin NVENC web UI toggle.** `https://media.nori.lan` → Dashboard → Playback → Hardware acceleration → Nvidia NVENC + tick codec boxes (h264/hevc/mpeg4/vp9/av1) → Save. OS-level GPU access is already live; this flips `<HardwareAccelerationType>` from `none` to `nvenc` in `/var/lib/jellyfin/config/encoding.xml`.

- **Sunshine remote-desktop pairing.** Deployed (`modules/desktop/sunshine.nix`); NVENC builds confirmed (`h264/hevc/av1_nvenc`). Outstanding: one-time Moonlight pairing.

  Pairing steps:

  1. **Clear stray instance** — `sunshine` user unit binds `graphical-session.target`, only autostarts on *fresh* Hyprland login (lock/unlock won't trigger). If a manually-started copy holds the ports: `kill` it or reboot so systemd owns it
  2. **MacBook side** — `brew install --cask moonlight`
  3. **Pair** — browse `https://workstation:47990` over tailnet, set admin creds, PIN-pair, launch "Desktop"
  4. **Verify** video + audio

  **Fallback** if NVIDIA KMS capture black-screens: `capSysAdmin = false` (wlr capture — Hyprland is wlroots-based) + rebuild.

  Design + plan: `docs/superpowers/specs/2026-05-22-sunshine-remote-host-design.md`, `docs/superpowers/plans/2026-05-22-sunshine-remote-host.md`.

- **MemoryHigh caps on heavy services** — process-exporter now publishes `namedprocess_namegroup_memory_bytes{memtype="resident",groupname=…,host=…}` to pi VM for all three workhorse hosts (workstation, pavilion, aurora). Wait ≥7 days of data, identify the slowest-growing services per host, cap each via `systemd.services.<n>.serviceConfig.MemoryHigh = "…G"`. Premature to cap blindly. Sample query: `topk(10, max_over_time(namedprocess_namegroup_memory_bytes{memtype="resident"}[7d]) - min_over_time(namedprocess_namegroup_memory_bytes{memtype="resident"}[7d])) / 1024 / 1024`. Special interest: aurora `gunicorn` (immich-ml — PyTorch, known leak shape).

## Deferred (tracked, not currently worked)

- **Remaining stabilisation (personal apps).** Phases 1-3 + 6-prep landed 2026-05-08 (CI + Renovate on all 4 app repos; zod validation on drinks-api; finnbydel → Astro + Hono; stateful apps → Drizzle + bun:sqlite; @sentry SDKs wired, no-op without DSN). Remaining: phase 4 (static sites → Cloudflare Pages, removes 3 attack surfaces from workstation), phase 5 (microvm.nix for drinks + finnbydel, kernel-level isolation for stateful apps that stay on workstation). Sentry activation when operator provisions projects: add 6 sops secrets `sentry-dsn-{heim,drinks-app,drinks-server,filmder,finnbydel-app,finnbydel-server}` to `secrets/apps.yaml`; update each module's environment block.

- **Remaining SSO candidates.** Second batch landed (Immich + Beszel native OIDC, Komga + calibre-web forward-auth). Still on the table:
  - **Native OIDC:** Komga could move from forward-auth to per-user OIDC if family members start wanting separate read-history; Spring Security OAuth2 config is verbose but doable.
  - **Skip / problematic:** Jellyfin (mobile/TV clients bypass cookie-based forward-auth; native SSO plugin has sharp historical edges). Radicale CalDAV clients can't follow forward-auth redirects, must stay on htpasswd. Glance/Gatus are intentionally public. Syncthing is single-admin. ntfy push API path exemption ends up too permissive to be worth gating the web UI alone.

- **Lower-priority appliance candidates.** Glance (status dashboard), Radicale (CalDAV/CardDAV) could move to Pi following the same split-module pattern as beszel/ntfy. Light, gain failure independence at near-zero cost. Not load-bearing — pursue when Pi has spare cycles.

- **Batch C: generated docs from live config.** Replace static "active services" + "host placement" + "snapshot policy" tables in `SERVICES.md` / `TOPOLOGY.md` / `STORAGE.md` with `nix eval`-driven output (`scripts/render-docs.sh` → `docs/auto/*.md`, gated by a `docs-fresh` flake check). Eliminates a class of doc drift entirely (executable docs don't decay). Roughly 1–2h to land.

## Promotion register (from INVARIANTS.md)

`[prose: unchecked]` claims worth mechanizing — detail in `INVARIANTS.md § promotion work-list`:

| Check | Promotes to | Catches |
|---|---|---|
| `disko-uses-by-id` | `[law]` — flake check, grep disko files | `/dev/nvme[0-9]` or `/dev/sda[0-9]?` leakage (NVMe enum drift wipes wrong disk) |
| `function-named-subdomains` | `[law]` — flake check, brand denylist | service-name leakage in `nori.lanRoutes` |
| `workhorse-vs-appliance-placement` | `[law]` — module assertion | service placement matches host role |
| `systemd-execstart-resolves` | `[law]` — flake check | ExecStart's first token resolves to closure path (incident 2026-06-03 class) |
| `effects-have-tests` *(added 2026-06-07)* | `[law]` — meta-check | every `modules/effects/<X>.nix` with Reader+Writer shape has matching `just test-<X>` recipe in `Justfile`. See `docs/RUNTIME_TESTS.md` |

## Idea backlog (no commitment)

- **UPS for workstation.** Single PSU is a non-goal for HA, but mid-write power loss on USB-attached IronWolf is a real recovery scenario. Cheap (~1500–3000 NOK for 600VA) insurance.
- **IronWolf Pro from USB to internal SATA.** When SATA capacity becomes available (PCIe HBA). USB enclosures have their own failure mode at the controller level.
- **`common-cpu-amd-pstate`** module on workstation hardware.
- **NVIDIA Wayland edge cases** (multi-monitor VRR, suspend/resume nuances). Not blocking; document fixes in `hardware.nix` as encountered.
- **CUDA/Ollama drift.** Ollama bundles its own CUDA libs; verify at install and pin nixpkgs version if it doesn't.
- **Home automation on the Pi.** No concrete use case currently.
