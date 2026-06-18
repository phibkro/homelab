{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:

/**
  ## workstation — Ryzen 5600X · 32 GB DDR4 · RTX 5060 Ti 16 GB (Blackwell)

  Workhorse-tier compute. Three NVMe-class drives + one USB-attached HDD:

   - **WD SN750 1 TB NVMe** — root + service state (`@`, `@home`,
     `@nix`, `@var-lib`, `@var-log`). disko at `./disko.nix`.
   - **Corsair MP510 960 GB NVMe** — cold replica of `/mnt/family/*`
     (btrbk receive endpoint, P14). disko at `./disko-mp510.nix`.
   - **Seagate IronWolf Pro 4 TB (USB)** — `@downloads` + `@streaming`
     for arr stack throughput. disko at `./disko-media.nix`.

  ## NVMe enumeration warning

  `nvme0n1` was NixOS root at install time; post-reboot the drives
  swapped. Disko configs target `/dev/disk/by-id/...` paths because of
  this. **Never touch `nvme0n1` without verifying the model string via
  `/dev/disk/by-id/`** — full constraint in CLAUDE.md hard rules. See
  `.claude/skills/gotcha-nvme-enumeration/`.

  ## Wake-on-LAN

  Pi's `wakeonlan` sender targets this host's MAC (`scripted-networking
  → systemd-network-link` config; P19 Aurora-migration). The combined
  shape is: aurora always-on serving family routes; workstation
  WoL-woken from pi when media access happens (Jellyfin / Samba /
  arr web UI).

  ## Sleep + GPU constraint

  NVIDIA Blackwell + `suspend-then-hibernate` hangs upstream (systemd
  #27559). Workstation uses manual `super+P` lock-then-suspend with
  the VRAM-preserve kernel param fix; PipeWire-aware idle inhibit
  prevents idle-sleep during ambient sound. Full debt note in
  `docs/roadmap.md § Architectural debt`.
*/

{
  imports = [
    /*
      AMD Ryzen 5600X (Zen 3) tweaks + SSD profile. The sibling
      common-cpu-amd-pstate (scaling-driver tuning) is not pulled
      in — add when the tuning becomes a measured win.
    */
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  # --- boot --------------------------------------------------------------

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];

  # CPU microcode updates.
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  /*
    Filesystems are emitted by ./disko.nix at install time. Do not declare
    fileSystems here; disko's NixOS module produces them from the disko
    config, and re-declaring would be a definition conflict.
  */

  /*
    Disk-backed swap behind zram (16 GiB compressed, configured in
    modules/machines/base/base.nix). Two roles:
      1. Overflow tier — zram absorbs most pressure in-memory; this
         catches what zram can't compress further. Observed pre-freeze
         on 2026-06-06 (zram pegged at 16 GiB for ~3 weeks before the
         UI froze under sustained memory pressure).
      2. Hibernation target — the kernel writes a compressed image of
         RAM here on `systemctl hibernate`. Sized at 32 GiB (= RAM) so
         hibernation succeeds even under heavy load; smaller swap risks
         "Cannot allocate memory" mid-hibernate. zram is RAM-backed and
         not usable for hibernation, so this disk swap is the only
         hibernation surface.

    Created out-of-band on @ subvol (not snapshotted by btrbk, which
    only covers @home / @srv-share / @var-lib) via
      sudo btrfs filesystem mkswapfile --size 32g /swapfile
    — handles NoCoW + no-compression + block preallocation in one step
    (btrfs-progs 6.1+). Disko config should bake this into the install
    path for future hosts.

    boot.resumeDevice + resume_offset (in kernelParams below) point the
    kernel at this swapfile on cold boot so it finds + restores the
    hibernation image. Filesystem UUID is the @ btrfs (root) UUID;
    offset is in btrfs-block units (4KiB), obtained via
      sudo btrfs inspect-internal map-swapfile -r /swapfile
    The value must be re-captured if the swapfile is ever recreated
    (different on-disk position → different offset). Last refresh:
    2026-06-15 grow-to-32g.
  */
  swapDevices = [ { device = "/swapfile"; } ];

  boot.resumeDevice = "/dev/disk/by-uuid/c87e6351-3b15-43fc-b276-45494258dd50";

  /*
    --- Wake-on-LAN ------------------------------------------------------
    P19 prerequisite: aurora (always-on) sends a magic packet over LAN
    to wake workstation when family-tier traffic actually needs it
    (jellyfin stream start, *arr scrape, samba /mnt/media access).
    Realtek RTL8125 (enp42s0) supports MagicPacket per ethtool's
    `Supports Wake-on: pumbg`. The `networking.interfaces.<n>.wakeOnLan`
    NixOS option emits a systemd-networkd `.link` file, which scripted
    networking (workstation uses `networking.useDHCP = true`) doesn't
    process — the NIC stays at `Wake-on: d`. A boot oneshot that runs
    `ethtool -s wol g` is the path that actually sets the policy under
    scripted networking; same pattern as `ironwolf-spindown` below.
  */
  systemd.services.wake-on-lan-enp42s0 = {
    description = "Enable MagicPacket WoL on enp42s0";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool -s enp42s0 wol g";
    };
  };

  /*
    --- IronWolf idle spindown -------------------------------------------
    4 TB Seagate IronWolf NAS HDD; ~5-7 W spinning at idle. Most media
    access is bursty (jellyfin transcode start, immich library import,
    btrbk hourly snapshot is metadata-only so doesn't require spin-up).
    20-min idle spindown trades ~50 kWh/year vs an ~8s spin-up latency
    on first access. NAS-tier drives are rated for far more start/stop
    cycles than consumer drives so the wear cost is acceptable.

    `-S 240` = 240 × 5s = 20 min spindown timer. Set on every boot
    because the drive forgets it across power cycles.
  */
  systemd.services.ironwolf-spindown = {
    description = "Set IronWolf 20min idle spindown timer";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.hdparm}/bin/hdparm -S 240 /dev/disk/by-id/ata-ST4000NE001-2MA101_WS24X543";
    };
  };

  /*
    --- gpu (nvidia open, RTX 5060 Ti / Blackwell) -----------------------

    Driver-package fallback ladder per docs/reference/topology.md § "GPU access":
      production  -> beta  -> latest  -> explicit mkDriver version
    Known: 580.119.02 fails to build on kernel 6.19 (vm_area_struct API
    change). 580.126.09 fixes it. If `production` resolves to .119 and
    6.19 is in use, fall back to `beta` or pin an older kernel.
  */
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    open = true; # open kernel module (driver 575+ / Blackwell)
    modesetting.enable = true;
    nvidiaSettings = true; # nvidia-settings GUI for the desktop session
    /*
      powerManagement.enable is meant to install nvidia-suspend/-resume
      systemd units that toggle NVreg_PreserveVideoMemoryAllocations
      around sleep transitions. Verified 2026-06-15 that those units
      are NOT actually installed under hardware.nvidia.open = true with
      driver 595.x — `systemctl list-unit-files 'nvidia-suspend*'` is
      empty, /sys/module/nvidia/parameters/NVreg_PreserveVideoMemoryAllocations
      is unset. Belt-and-braces: pass the param at module load via
      boot.kernelParams below. Keep this option = true so future driver
      versions that DO ship the hooks pick them up automatically.
    */
    powerManagement.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  /*
    Two unrelated boot-time concerns:

    nvidia.NVreg_PreserveVideoMemoryAllocations=1 — Force VRAM
    preservation across s2idle suspend. Without this, the GPU loses
    video memory contents during sleep and resume hangs the
    compositor (TTY1 paints background, mouse dead, eventual Hyprland
    crash — reproduced 2026-06-15 testing super+P bind). NVIDIA's
    production driver doesn't auto-set this under the open Blackwell
    module; setting it on the kernel command line ensures the value
    lands before first module init. State-of-art workaround per
    NVIDIA developer forum thread #327297 (RTX 5070 Ti, same arch).

    resume_offset — Physical byte offset of /swapfile within the @
    btrfs subvolume's underlying device. Paired with boot.resumeDevice
    above so the kernel can find the hibernation image written by
    `systemctl hibernate`. Re-capture via
    `sudo btrfs inspect-internal map-swapfile -r /swapfile` after any
    swapfile recreation; today's value is from the 2026-06-15
    grow-to-32g run.
  */
  boot.kernelParams = [
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "resume_offset=42773523"
    /*
      Disable legacy 8250 serial port enumeration. /proc/tty/driver/serial
      shows COM1 (16550A) with zero traffic + three phantom ports at
      02F8/03E8/02E8 with `uart:unknown` (port addresses BIOS-reserved,
      no chip behind them). systemd creates /dev/ttyS{0..3}.device units
      for all four and udev waits ~4s on each at boot — pure cost, no
      value, this host never uses serial for console or anything else.
    */
    "8250.nr_uarts=0"
  ];

  /*
    Don't block boot on DHCP lease acquisition. Default `any` waits for
    the first interface to fully lease, ~10s on this host. `if-carrier-up`
    considers dhcpcd done once carrier (ethernet link) is up, which is
    near-instant on a plugged-in NIC; the actual lease arrives in the
    background. network-online.target reaches active much sooner;
    services that need full network can still wait on their own targets.
  */
  networking.dhcpcd.wait = "if-carrier-up";

  /*
    Canonical GPU device list for services that opt in via
    accelerationDevices / DeviceAllow. Default in modules/infra/capabilities/gpu.nix
    is empty; host explicitly enumerates what's present so Pi (no
    GPU) doesn't get phantom device references.
  */
  nori.gpu.nvidiaDevices = [
    "/dev/nvidia0"
    "/dev/nvidiactl"
    "/dev/nvidia-uvm"
  ];

  /*
    Build aarch64 closures locally for pi via binfmt emulation.
    Cheaper than cross-compilation; closer to native build correctness.
  */
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  nixpkgs.hostPlatform = "x86_64-linux";
}
