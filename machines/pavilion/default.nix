{
  config,
  lib,
  inputs,
  ...
}:

# pavilion — HP Pavilion g6, retasked as an agent quarantine host.
#
# ── Why a separate machine ─────────────────────────────────────────
# `nixpkgs-agent` (and any future agent-driven loop) runs the model +
# bash + nix-build in `box --pi` on workstation today. That's fine for
# the iterative phase, but the long-term shape is:
#
#   * untrusted-compute should NOT share a kernel with the workhorse's
#     state-rich services (Caddy, Authelia, Jellyfin, Vaultwarden …)
#   * agent outputs are the only artefact we keep — everything else is
#     ephemeral by construction (no logs to preserve, no sessions to
#     resume, no SSH key inbound from agent tier)
#   * a reboot should be a safety valve, not a recovery procedure
#
# Pavilion is the realisation of that: a NixOS host designed to be
# wiped every boot.
#
# ── Posture ────────────────────────────────────────────────────────
# 1. **Root on tmpfs via nix-community/impermanence.** Everything not
#    under `/persist` vanishes on reboot — including agent worktrees,
#    journald, /var/tmp, partial nix-build artefacts. Only ssh host
#    keys, tailscale state, and machine-id survive the reboot.
# 2. **No GPU.** Inference is offloaded to workstation's 5060 Ti over
#    tailnet (`http://workstation.saola-matrix.ts.net:11434` — the
#    `tag:agent → tag:privileged:11434` ACL rule documented below).
# 3. **No claude-code, no GitHub credential.** Per the
#    `agent`-role posture in modules/effects/hosts.nix: claude-code is
#    the operator's trusted hands and lives on workstation; the
#    pavilion agent runs only `pi` (badlogic/pi-mono) inside
#    `box --pi --pwd-ro` when the worktree lives under any sensitive
#    tree (homelab is not on this host anyway).
# 4. **Tailnet ACL split.** Applied via the Tailscale admin UI (NOT in
#    this flake — ACLs aren't a nixos option). The shape we agreed:
#
#      tag:privileged  — workstation, macbook (full intra-tag access)
#      tag:appliance   — pi
#      tag:agent       — pavilion
#
#    Privileged → anything (operator's tools work as today).
#    Appliance / agent → privileged: only :11434 (ollama) and :443
#    (caddy). NOT SSH. Default-deny otherwise. SSH inbound to
#    appliance/agent allowed from privileged only.
#
# ── Imports ────────────────────────────────────────────────────────
# Flat imports per the homelab convention: pull only what this host
# needs, NOT modules/server/default.nix. Most service modules
# (Caddy, Authelia, Jellyfin, the *arr stack) make no sense here.

{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager

    ../../modules/common # base + users + sops + tailscale + lib options

    # Notably absent:
    #   modules/server/default.nix    — no LAN services
    #   modules/desktop/default.nix   — headless

    ./hardware.nix
  ];

  # ── home-manager-as-NixOS-module ──────────────────────────────────
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    backupFileExtension = "hm-backup";
    users.nori.imports = [ ./home.nix ];
  };

  # ── Boot ───────────────────────────────────────────────────────────
  # GRUB on the BIOS boot partition disko carved out — this g6 unit is
  # BIOS-firmware (not UEFI; confirmed via `[ -d /sys/firmware/efi ]`
  # on the live ISO returning false). disko derives the target device
  # from the disko.devices.disk.main config (see disko.nix); we just
  # toggle GRUB on and explicitly turn EFI off so its assertions match
  # the BIOS firmware.
  boot.loader.grub = {
    enable = true;
    efiSupport = false; # BIOS path; no /boot/EFI
  };
  boot.loader.systemd-boot.enable = false;

  # ── btrfs-rollback impermanence ───────────────────────────────────
  # Tmpfs root would eat ~1.8 GB of the 3.6 GB RAM on this host — too
  # expensive. Instead we keep / on a btrfs subvol (@root) and roll it
  # back to the empty @root-blank snapshot in early initrd, before
  # systemd brings up sysroot. End-state property is the same: every
  # boot starts from a clean root; only paths under /persist
  # (declared below) survive.
  #
  # The rollback runs in initrd-systemd before the actual / mount, so
  # we don't risk capturing in-flight files into the snapshot. The
  # @root subvol is delete-and-recreate from @root-blank.
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.services.rollback = {
    description = "Rollback @root to @root-blank for impermanence";
    wantedBy = [ "initrd.target" ];
    after = [ "dev-disk-by\\x2dlabel-pavilion\\x2droot.device" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /btrfs_tmp
      mount -t btrfs /dev/disk/by-label/pavilion-root /btrfs_tmp
      if [ -e /btrfs_tmp/@root ]; then
        mkdir -p /btrfs_tmp/old_roots
        timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/@root)" "+%Y-%m-%d_%H:%M:%S")
        mv /btrfs_tmp/@root "/btrfs_tmp/old_roots/$timestamp"
      fi
      btrfs subvolume snapshot /btrfs_tmp/@root-blank /btrfs_tmp/@root
      umount /btrfs_tmp
    '';
  };

  # ── Networking ─────────────────────────────────────────────────────
  # networking.hostName injected from the registry key in flake.nix.
  networking.useDHCP = lib.mkDefault true;

  # Tailscale routing role — agent host does NOT advertise routes or
  # serve as an exit node (workstation is the workhorse, pi is the
  # appliance; this host is sized to consume).
  services.tailscale.useRoutingFeatures = lib.mkForce "none";

  # Firewall: deny all inbound on tailnet except SSH (operator access).
  # The ACL above tightens this further per-source-tag; defense in
  # depth keeps the deny-by-default property local to the host even
  # if the ACL is mis-applied.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    22 # SSH inbound — gated by ACL to tag:privileged only
  ];

  # ── Impermanence ──────────────────────────────────────────────────
  # The contract: everything under `/` is ephemeral. Only the paths
  # listed below survive a reboot, by being bind-mounted from
  # `/persist` (a btrfs subvolume on the same HDD — see disko.nix).
  # The "clean state" before binds is achieved by the rollback service
  # above, which snapshots @root-blank onto @root in early initrd.
  #
  # Why each entry persists:
  #   * /etc/ssh — host keys; without these, every boot re-keys and
  #     Tailscale + operator SSH would prompt on every login
  #   * /var/lib/tailscale — node identity + ACL state; otherwise
  #     re-auth every boot (manual interactive flow, defeats agent)
  #   * /var/lib/nixos — NixOS UID/GID stability; without this,
  #     /home/nori would re-uid on every boot
  #   * /var/log/journal — KEPT to preserve activation/boot logs;
  #     if log mass becomes a problem move to /var/log -> tmpfs and
  #     drop this entry, accept losing history.
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/etc/ssh"
      "/var/lib/tailscale"
      "/var/lib/nixos"
      "/var/log/journal"
      # iwd holds the wifi SSID + PSK after first connection. Without
      # this, every reboot loses wifi and the host falls back to
      # whatever ethernet config it has — for a roaming laptop that
      # means going offline. Caught the hard way during first deploy
      # (no wifi config = no network = no SSH).
      "/var/lib/iwd"
    ];
    files = [
      "/etc/machine-id"
    ];
  };

  # ── Wifi (iwd, declarative-state) ─────────────────────────────────
  # iwd is the modern wifi daemon NixOS uses on installer images. We
  # enable it here so the installed system can keep the wifi
  # connection alive. SSID + PSK live in /var/lib/iwd (persisted
  # above); the operator runs `iwctl station wlan0 connect <SSID>`
  # once on first boot, then it's permanent.
  networking.wireless.iwd.enable = true;

  # Disable wpa_supplicant explicitly — iwd is the chosen wifi stack
  # and the two conflict if both are enabled.
  networking.wireless.enable = false;

  # ── SSH ───────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      # `prohibit-password` lets root in via SSH key but not via
      # password — needed for nixos-anywhere redeploys (which use
      # root over SSH). Operator's day-to-day SSH is the `nori` user.
      # mkForce overrides modules/common/users.nix's safe-default
      # "no" — this host's role specifically requires root key login.
      PermitRootLogin = lib.mkForce "prohibit-password";
    };
  };

  # Operator's pubkey authorized for both `nori` (interactive) and
  # `root` (nixos-anywhere deploys). nori-station@github is the
  # workstation's ed25519 key — same key authorized on other lab hosts.
  users.users.nori.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgBC1J2CYrhdwFerwCa9GZD15I03vqS07bFtiYRl2FU nori-station@github"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgBC1J2CYrhdwFerwCa9GZD15I03vqS07bFtiYRl2FU nori-station@github"
  ];

  # ── Posture assertions ────────────────────────────────────────────
  # Make the agent posture failure modes loud at eval time rather than
  # discovering them in production.
  assertions = [
    {
      assertion = config.nori.hosts.${config.networking.hostName}.role == "agent";
      message =
        "pavilion's role must be 'agent' in flake.nix identityFor "
        + "(otherwise the impermanence/no-backup posture is silently "
        + "wrong)";
    }
  ];
}
