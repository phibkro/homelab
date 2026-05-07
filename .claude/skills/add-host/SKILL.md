---
description: Add a new NixOS host to this homelab flake — wires the host folder, identity registry, role tag (workhorse vs appliance), concerns picked from `modules/{common,server,desktop}`, sops recipient onboarding, and first-boot install path. Eval fails if the folder + registry entry don't both land.
when_to_use: User mentions adding a new physical or virtual machine to the flake — phrases like "add a new host", "set up nori-X", "another machine", "new device for the homelab", "bring under the flake", "I'm getting a new <Pi/server/laptop>".
---

# Add a new homelab host

Authoritative procedure. The flake's `readDir ./machines/` + `genAttrs hostNames` + `identityFor` lookup means the folder structure IS the host enumeration; missing either side fails eval.

## Decision summary up front

1. **Role**: `workhorse` (heavy compute / state / GPU; backed up locally and offsite) or `appliance` (observability + alert plane that survives workhorse failure; anti-write storage; backups via skip-only). Drives concern selection + the placement assertion in `modules/effects/backup.nix`.
2. **Architecture**: `x86_64-linux` or `aarch64-linux`. Pi-class is aarch64; needs `nixos-hardware/raspberry-pi-4` import + sd-image build path; station builds Pi closures via aarch64 binfmt emulation.
3. **Install path**: bare-metal disko (workhorse-class x86) vs sd-image build + dd to flash (appliance-class aarch64) vs UTM dry-run (transient).
4. **Concern selection**: `modules/common` (always) + `modules/server` (workhorse bundle) + `modules/desktop` (graphical). Or for appliance: `modules/common` + flat imports of specific modules the host needs.

## Step-by-step

### 1. Create the host folder

```bash
mkdir machines/<name>
touch machines/<name>/{default,hardware}.nix
```

The folder name IS the hostname. `flake.nix`'s `mkHost` injects `config.networking.hostName = <folder name>`. Don't redeclare it inside the host's `default.nix`.

### 2. Add identity to the registry

```nix
# flake.nix → identityFor
<name> = {
  tailnetIp = "100.X.Y.Z";  # assigned after first tailscale auth; placeholder OK initially
  lanIp = "192.168.1.N";    # static lease on the router; null if none
  role = "workhorse";       # or "appliance"
};
```

Eval fails if you skip this — `genAttrs hostNames mkHost` needs `identityFor.<name>`.

For a transient host (UTM dry-run target like `vm-test`), placeholder values that satisfy the schema are fine; nothing cross-host references them.

### 3. Write hardware.nix

Required minimum:

```nix
{ ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";  # or "aarch64-linux"

  # Host-specific stuff — disks via disko, kernel modules, hardware-specific sysctl.
  # Workhorse-class x86: import disko + ../hardware/workstation/disko.nix shape
  # Pi-class aarch64: import nixos-hardware.nixosModules.raspberry-pi-4 + the sd-image-aarch64 module
}
```

GPU host? Set `nori.gpu.nvidiaDevices = [ "/dev/nvidia0" "/dev/nvidiactl" "/dev/nvidia-uvm" ]` here.

Anti-write storage host (USB flash, SD card)? See `machines/pi/hardware.nix` — `swapDevices = []`, `journald.Storage=volatile`, `vm.mmap_rnd_bits` aarch64 fixup if applicable.

### 4. Write default.nix

Workhorse pattern (everything bundled):

```nix
{ inputs, lib, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ../../modules/common
    ../../modules/server
    ../../modules/desktop  # if graphical
    ./hardware.nix
    # ./disko.nix or other host-specific files
  ];
  networking.useDHCP = lib.mkDefault true;
}
```

Appliance pattern (flat imports — Pi precedent):

```nix
{ inputs, lib, modulesPath, config, ... }:
{
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
    ../../modules/common
    # Pick specific server modules the host needs (don't import the bundle):
    ../../modules/server/blocky.nix
    ../../modules/server/gatus.nix
    ../../modules/server/beszel/{hub,agent}.nix
    # ...
    ./hardware.nix
  ];
}
```

Don't redeclare `networking.hostName` — injected from the folder name.

### 5. Sops onboarding

```bash
# Derive the host's age key from its SSH host key
ssh-keyscan -t ed25519 <ip> | ssh-to-age
# → age1...

# Add as a recipient in .sops.yaml
$EDITOR .sops.yaml
# Re-encrypt all secrets to the expanded set
sops updatekeys secrets/secrets.yaml
```

If the host has a `beszel-agent`, it'll need a per-host SSH key in sops as `beszel-agent-key-<hostname>` — add that secret (and on the receiver Beszel hub side, add the agent's pubkey).

### 6. First boot

**Workhorse-class x86** — see `docs/baremetal-install.md`. Disko at install, not deferred.

**Appliance-class aarch64** — sd-image build path:

```bash
# Build the image (cross-compile via binfmt on station, or natively if you have an aarch64 builder)
nix build .#nixosConfigurations.<name>.config.system.build.sdImage

# Verify size + content
ls -lh result/sd-image/

# Flash to the target media
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

First boot picks up DHCP. Manual tailscale auth:

```bash
ssh nori@<lan-ip>
sudo tailscale up --ssh --advertise-routes=192.168.1.0/24 --advertise-exit-node --hostname=<name>
# (drop --advertise-routes/exit-node for non-router-class hosts)
```

After first auth, capture the tailnet IP and update `flake.nix` `identityFor.<name>.tailnetIp`.

### 7. Update CLAUDE.md "Current state"

Topology + service placement section. Mention the host's role and any cross-host service split it participates in. Per the "On every structural change" rubric — drift compounds, do this immediately.

If memory needs updating (cross-session host topology fact), update `~/.claude/projects/.../memory/`.

### 8. Verify

```bash
# From station:
just remote <name> rebuild               # rsync + rebuild
just remote <name> status                # systemctl --failed should be empty
ssh nori@<name>.saola-matrix.ts.net 'hostname && uptime'

# Verify the host's tailnet identity:
tailscale status | grep <name>
```

The `nix flake check` derivations now also evaluate this host — host-aware assertions (e.g. appliance-no-paths-backups) fire if you violate the role contract.
