---
summary: Hosts, hardware, roles, the topology registry, GPU access, resource
  caps. The "what runs where" reference. Service placement assertions and the
  workhorse/appliance role split derive from the role tag on each host.
---

# Topology

Two persistent hosts on a single residential network, plus a Mac that
home-manager-administers locally. Roles are typed; placement assertions enforce
them; cross-host references go through the registry, never IP literals.

## Hosts at a glance

| Host | Role | OS | Arch | Hardware | Primary job |
|---|---|---|---|---|---|
| **workstation** | `workhorse` | NixOS 26.05 | x86_64 | Ryzen 5600X · 32GB DDR4 · RTX 5060 Ti 16GB (Blackwell) | HTTP entry plane (Caddy + Authelia), GPU-bound services, state-heavy services, daily-driver desktop |
| **pi** | `appliance` | NixOS 26.05 | aarch64 | Raspberry Pi 4 8GB · USB-boot from Samsung FIT 128GB | Observability hub, alert plane, DNS forwarder, Tailscale subnet router + exit node |
| **macbook** | (no role) | macOS · standalone home-manager | x86_64-darwin | Intel Mac | Daily-driver laptop; Nix-managed CLI baseline + brew for Mac-only packages |

Failure domain independence: workstation and pi share no storage, no PSU, no critical dependency in the boot path. Either host's failure does not block the other's.

## Workstation drives

| Drive | OS / use | Notes |
|---|---|---|
| WD Black SN750 1TB NVMe | NixOS root | btrfs, six subvolumes, label `nixos`, disko-managed |
| Corsair Force MP510 960GB NVMe | **Windows — never touch** | Preserved untouched; multi-boot via UEFI. `nvme-Force_MP510_2031826300012953207B` is the by-id |
| Seagate IronWolf Pro 4TB (USB) | Media storage | btrfs, five subvolumes, label `ironwolf-storage`, disko-managed |

**NVMe enumeration is unstable across reboots.** `nvme0n1` was NixOS root at install time; post-reboot the drives swapped. Disko configs target `/dev/disk/by-id/...` paths for this reason. See `.claude/skills/gotcha-nvme-enumeration/`.

## Pi posture

USB-then-SD boot order via EEPROM `BOOT_ORDER=0xf41`. Anti-write storage posture:

```nix
swapDevices = [ ];
services.journald.extraConfig = "Storage=volatile";
boot.kernel.sysctl."vm.mmap_rnd_bits" = 18;  # aarch64 fixup
```

SD-card / flash wear is the #1 Pi failure mode. Volatile journald + no swap mitigate.

**Restic-as-target deferred:** Pi can host the workstation restic repo only when a real disk replaces the FIT — the anti-write posture rules out daily restic to flash.

## Topology registry (`nori.hosts`)

Cross-host references go through the registry, **never IP literals**. Schema in `modules/effects/hosts.nix`; values in `flake.nix` `identityFor`. A `readDir` over `./machines/` drives both `nixosConfigurations` enumeration and the registry — adding a host is "create the folder + add identity"; either omission fails eval.

```nix
config.nori.hosts.<name> = {
  role = "workhorse" | "appliance";  # typed; drives placement assertions
  tailnetIp = "100.x.y.z";            # the ONLY place IP literals live
  lanIp = "192.168.1.z";
  # … hardware-derived context, see modules/effects/hosts.nix
};
```

The `role` field drives the placement assertion in `modules/effects/backup.nix`: appliance hosts cannot use `paths`-based backups (they're observers, not state holders).

**Consumer-side lookup** (this is how cross-host wiring stays IP-literal-free):

```nix
# In a service module on workstation that reverse-proxies to pi:
nori.lanRoutes.metrics = {
  port = 8090;
  host = config.nori.hosts.pi.tailnetIp;   # ← never "100.100.71.3"
  monitor = { };
};
```

The `forbidden-patterns` flake check fails the build on a stray `100.x.y.z` literal anywhere outside `flake.nix`'s `identityFor`.

## Service placement

| Cluster | Where | Why |
|---|---|---|
| HTTP entry plane (Caddy + Authelia) | workstation | Workhorse owns user-facing surface; tailnet routes through here |
| GPU-bound (Ollama, Jellyfin NVENC, Immich CUDA ML) | workstation | Only host with the GPU |
| State-heavy (Vaultwarden, Radicale, *arr stack, Immich, file shares) | workstation | Fate-sharing: when workstation is down they're useless either way |
| Observability + alert plane (Beszel hub, Gatus, ntfy server) | pi | Must survive workstation outage — that's *when* they fire |
| DNS (Blocky forwarder) | pi (primary) | Pushed to tailnet devices via Tailscale global-nameserver |
| DNS (Blocky self-hosted) | workstation (secondary) | Auto-generates `*.nori.lan` map; survives Pi outage |
| Network plumbing (subnet router + exit node) | pi | Appliance role; opt-in per device for exit node |

The placement test is **fate-sharing breaks the function**, not "feels lightweight." See `docs/CONCEPTS.md` § fate-sharing.

## Cross-host services

Live: Beszel hub (`metrics.nori.lan`), ntfy server (`alert.nori.lan`). Both follow the **split-module pattern** — daemon module on the host that runs it, client/proxy module on every host. The cross-host Caddy lanRoute is gated `lib.mkIf config.services.caddy.enable` so the daemon-host's Blocky stays in pure forwarder mode.

Add another via `/relocate-to-pi`. Precedents: `modules/server/beszel/{hub,agent}.nix`, `modules/server/ntfy/{server,notify}.nix`.

## GPU access pattern

Services that need the GPU set `accelerationDevices` (or systemd `DeviceAllow`) from `config.nori.gpu.nvidiaDevices` — single source of truth in `modules/effects/gpu.nix`.

| Service | Status | Resource |
|---|---|---|
| Ollama (CUDA) | live | 14+ GiB VRAM at idle with model loaded |
| Immich (CUDA ML + NVENC) | live | NVENC encode, ML inference |
| Jellyfin (NVENC) | OS-level live | Web-UI flag still off (ROADMAP item) |

`hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.production` — 595.58.03 on 26.05, Blackwell support landed. Fallback ladder if production breaks: `production` → `beta` → `latest` → explicit `mkDriver` pin.

## Resource caps (where it matters)

| Service / system | Cap | Reason |
|---|---|---|
| `immich-machine-learning.serviceConfig` | `CPUQuota=600%`, `MemoryMax=16G` | Guards the userspace-CPU-starvation pattern that wedged the host 2026-04-28 (rtkit canary thread starved 4+ minutes; commit `c0a557d`) |
| `zramSwap` on workstation | 16 GiB compressed | Required for nvcc/CUDA builds; previously OOM'd + hard-hung the host |
| `swapDevices` on pi | `[ ]` (no swap) | Anti-write posture for flash storage |

## Operator facts

- Single user `nori`, passwordless wheel sudo, SSH key-only.
- CPU cooler repasted 2026-04-29 — sustained 12-thread load ~72°C (was 95°C TJ_max throttling pre-repaste).

## Adding a host

See `/add-host`. Short version:

1. Create `machines/<name>/` (folder name = `networking.hostName` — injected, don't redeclare).
2. Add an `identityFor` entry in `flake.nix` with `role`, `tailnetIp`, `lanIp`. Eval fails if folder or registry is missing.
3. **Add the new host's age public key** (derived from its SSH host key via `ssh-to-age`) to `.sops.yaml` and run `sops updatekeys secrets/secrets.yaml` to re-encrypt existing secrets so the new host can decrypt them. Without this, sops secrets are unreachable on first boot.
4. First boot → `tailscale up` → approve in admin console for subnet route / exit node if applicable.
