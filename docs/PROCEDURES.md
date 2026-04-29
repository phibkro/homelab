# Procedures

Step-by-step recipes for common structural operations. Read on demand when the matching intent arises — these are *mechanical* lookup material, not always-loaded context.

Routed from `CLAUDE.md` "Procedures" pointer. If you find yourself reasoning out one of these from first principles, stop and read the relevant section here instead.

---

## How to add a new service

1. Create `modules/server/<service>.nix` (loose) or land inside an existing tightly-coupled folder like `modules/server/arr/`. Folders signal coupling; flat = independent.
2. Enable the service module.
3. Apply default-deny FS hardening (`ProtectHome = lib.mkForce true;` + `TemporaryFileSystem` + `BindReadOnlyPaths`; full snippet in `docs/CONVENTIONS.md`).
4. Declare `nori.lanRoutes.<name> = { port = N; monitor = { }; };` for HTTPS access via Caddy + auto-monitoring.
5. Declare `nori.backups.<name>` — either `paths = [ ... ]` for what to back up, or `skip = "<reason>"` for explicit opt-out. Schema requires one or the other; `every-service-has-backup-intent` flake check fails the build if you forget. DynamicUser services point at `/var/lib/private/<name>` (the symlink target, not the symlink itself).
6. Append the new file to `modules/server/default.nix` (loose) or the relevant cluster's `default.nix` (e.g. `modules/server/arr/default.nix`). Coupled clusters import their own siblings via `default.nix`; loose services land in the top-level imports list.
7. If the service needs secrets: `sops secrets/secrets.yaml` (env-file format `KEY=VALUE` if consumed via `EnvironmentFile`).
8. If the service needs SSO: `just oidc-key <name>` → paste raw + hash into sops → declare `nori.lanRoutes.<name>.oidc = { clientName; redirectPath; };` in the same module → wire `EnvironmentFile = config.sops.templates."oidc-<name>-env".path;` + `SupplementaryGroups = [ "keys" ];` on the systemd unit. See `docs/CONVENTIONS.md` "Authelia OIDC pattern".
9. If the service needs GPU access: set its `accelerationDevices` (or systemd `DeviceAllow`) to `config.nori.gpu.nvidiaDevices`. The list lives in `modules/lib/gpu.nix`.
10. `just rebuild` (from Mac) or `nh os switch . -H nori-station` (from the host).
11. Commit (Conventional Commits — type + scope + tight summary).

---

## How to add a new host

1. **Create the host folder**: `mkdir hosts/<name>`. The folder name IS the hostname — `flake.nix`'s `mkHost` injects `config.networking.hostName = <folder name>`, and `readDir` over `./hosts/` is what populates `nixosConfigurations`. No separate "register the host" step needed for the configuration list.
2. **Add an `identityFor.<name>` entry** in `flake.nix`: `tailnetIp` (Tailscale-assigned, see admin console after first auth), `lanIp` (static lease on the router; null if none), `role` (`workhorse` or `appliance`). The genAttrs lookup fails eval if you skip this — folder without identity is a build error, by design.
3. **Write the host's config files** under `hosts/<name>/`: at minimum `default.nix` (imports + per-host concerns) and `hardware.nix` (`nixpkgs.hostPlatform`, disk layout import, kernel modules). Don't redeclare `networking.hostName` — it's injected from the folder name.
4. **Pick concerns** the host plays. Workhorse-class: import `../../modules/common` + `../../modules/server` + optionally `../../modules/desktop`. Appliance-class: import `../../modules/common` + flat imports of the specific server modules the host needs (per `nori-pi`'s precedent — the bundle is too coarse for appliance roles).
5. **Sops**: derive the host's age public key (`ssh-keyscan -t ed25519 <ip> | ssh-to-age` from a host with sops + age installed). Add as a recipient in `.sops.yaml`, then `sops updatekeys secrets/secrets.yaml` to re-encrypt to the expanded set.
6. **First boot**: install via the appropriate runbook (`docs/baremetal-install.md` for x86 metal, sd-image build via `nix build .#nixosConfigurations.<name>.config.system.build.sdImage` for aarch64 Pi-class). Manual `tailscale up` for first auth.
7. **Update `CLAUDE.md` "Current state" → Topology** with the new host's role and any cross-host service split it participates in. Update memory if cross-session facts shifted (per `~/.claude/projects/.../memory/`).
8. **Verify**: deploy from another host, confirm `hostname` matches folder, `systemctl --failed` empty, `tailscale status` shows up.

`vm-test` is the worked example of a stripped-down host: `hosts/vm-test/{default,hardware}.nix` + `identityFor.vm-test` placeholder. No backups, no Caddy, no observability — just enough for `nix build .#nixosConfigurations.vm-test` to succeed as a dry-run target.

---

## How to relocate a service to nori-pi

Pattern established by the beszel hub (commit b4499ee) and ntfy server (commit 9e0b2b6) migrations. Use when a service belongs in the appliance role (observability, alerting, DNS — see CLAUDE.md "What's the bias" → "Workhorse-by-default").

1. **Split the module** at `modules/server/<service>/{daemon,client}.nix`. The daemon part (the actual server) goes on Pi; the client/proxy part goes on every host that talks to it. Folder = coupling.
2. **Cross-host lanRoute** lives in the always-imported file (the client/notify side), wrapped in `lib.mkIf config.services.caddy.enable`. This way only the Caddy host (station) registers the route — Pi's Blocky stays in pure forwarder mode and the canonical service host owns the `*.nori.lan` map.
3. **Backend `host` field** in the lanRoute reads from the topology registry (`config.nori.hosts.<n>.tailnetIp`), never a literal. The host name in the lookup (e.g., `nori-pi`) is the topology coupling — if the daemon moves, change the name in the lookup, not an IP. See `modules/lib/hosts.nix` for the registry; values live in `flake.nix` `identityFor`.
4. **Per-host config** that varies by hostname (sops secret names, message templates) reads `config.networking.hostName` rather than introducing options.
5. **Hardware-specific FS gates** read existing registries (e.g., `config.nori.gpu.nvidiaDevices != [ ]` for NVIDIA `/dev/*` exposure) rather than per-service flags.
6. **State migration** is usually NOT worth it for non-load-bearing data (metrics, ephemeral caches). Daemon comes up empty on Pi and rebuilds from sops + first-use. Document the decision in the commit + the daemon module's header.
7. **`nori.backups.<n>.skip`** on the Pi-hosted daemon citing the anti-write storage posture (see `hosts/nori-pi/hardware.nix`). Don't add Pi-local restic until the planned fast-restore disk lands.
8. **Update `modules/server/default.nix`** (station's bundle) to import only the client side. Update `hosts/nori-pi/default.nix` to import both sides.
9. **Deploy order: Pi first** so the daemon is up before station's `services.<service>` config drops out and Caddy starts proxying cross-host.
10. **Verify end-to-end** via the canonical URL (e.g., `curl -fsS https://alert.nori.lan/v1/health`) — exercises DNS → Caddy → cross-host tailnet → daemon all in one call.
