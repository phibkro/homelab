{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:

/**
  aurora — retired Asus N552V (i7-6700HQ, 12 GB RAM, GTX 950M
  Maxwell, dead battery). Always-on family vault and application tier;
  Immich machine learning is co-located here so Workstation's 5060 Ti stays
  dedicated to interactive compute.

  ── Why it exists ──────────────────────────────────────────────────
  Aurora owns `/mnt/family/*`, the OneTouch restic target, and family-facing
  applications such as Immich, Navidrome, Vaultwarden, Paperless, and Komga.
  Keeping this tier always-on makes it independent of Workstation sleep. The
  950M also absorbs Immich's CLIP/face/OCR pipeline without evicting Ollama.

  ── Posture ────────────────────────────────────────────────────────
  * Stateful and backup-critical — family datasets live on the Toshiba HDD,
    service state is protected by local restic jobs, and btrbk replicates the
    irreplaceable family tier to Workstation.
  * No impermanence — service databases and ML weights need durable local
    state. Regular btrfs root.
  * Family services are reached through Pi's Caddy over tailnet; Samba is the
    deliberate direct file-sharing exception.
  * No claude-code, no operator GitHub credential. Operator's daily
    driver stays on workstation.
*/

{
  imports = [
    inputs.disko.nixosModules.disko

    # Notably absent:
    #   modules/machines/desktop/default.nix — headless

    ./hardware.nix
    ./disko-onetouch.nix
    ./disko-family.nix
  ];

  /*
    Aurora doesn't proxy syncthing through Caddy (the sync.* lanRoute
    is workstation-pinned). Expose the WebUI on tailnet directly for
    setup. Audience is operator only; access is gated by tailnet trust.
  */
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8384 ];

  /*
    Backup infrastructure for aurora's family-tier services. The
    cross-cutting `modules/infra/backup/restic.nix` is gated
    workstation-only by data ownership; aurora declares its own
    target here. The OneTouch HDD lives on aurora, so aurora's own
    backups land LOCAL at /mnt/backup — bypassing SFTP. Remote
    clients (workstation, pi) reach the same drive via the SFTP
    target declared by the restic-target inventory workload.
  */
  sops.secrets.restic-password = {
    owner = "root";
    mode = "0400";
  };
  nori.backupTargets.onetouch = {
    repository = "/mnt/backup";
    description = "Aurora-local OneTouch HDD (P13 dest). Aurora's own restic backups write here directly; remote hosts reach the same drive through the restic-target workload.";
  };
  /*
    Aurora-side tmpfiles:
     - /var/backup for Pattern C2 prepareCommands (vaultwarden's sqlite
       VACUUM INTO, etc.).
     - /mnt/family/library/{books,comics,manga} owned by `media` group
       so calibre-web + komga + suwayomi can write their initial empty-
       library state (each runs as its own user, all join `media`). The
       library
       subvol root is created root:root by disko; without these the
       services restart-loop with "Invalid Calibre library" because
       their pre-start can't `mkdir -p` inside it. Mirrors the pattern
       arr/shared.nix uses on workstation for /mnt/media/library/*.
  */
  systemd.tmpfiles.rules = [
    "d /var/backup                    0755  root  root  -"
    "d /mnt/family/library            02775 root  media -"
    "d /mnt/family/library/books      02775 root  media -"
    "d /mnt/family/library/comics     02775 root  media -"
    "d /mnt/family/library/manga      02775 root  media -"
    "d /mnt/family/library/music      02775 root  media -"
    "d /mnt/family/library/papers     02775 root  media -"
  ];

  /*
    `media` group needs to exist for the tmpfiles + calibre-web/komga
    group membership. arr/shared.nix declares it on workstation; aurora
    declares its own here (the group is per-host).
  */
  users.groups.media = { };

  /*
    nori in `media` so syncthing (runs as nori:users) can write to the
    /mnt/family/library/* tree, which is 02775 root:media per the
    tmpfiles above. Mirrors modules/machines/workstation/default.nix:53. Without
    this, syncthing logs `mkdir /mnt/family/library/<X>/.stfolder:
    permission denied` and the folder fails initial scan.
  */
  users.users.nori.extraGroups = [ "media" ];

  /*
    ── Boot ───────────────────────────────────────────────────────────
    2016 laptop with UEFI — assume systemd-boot. If first boot reveals
    legacy BIOS, flip to GRUB (see modules/machines/pavilion/default.nix for
    the BIOS-mode shape).
  */
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  /*
    MOTD additions on top of the universal core (modules/infra/
    rust-motd.nix) — iwd is laptop-specific, immich-ml is aurora's
    reason for existing.
  */
  programs.rust-motd.settings.service_status = {
    iwd = "iwd";
    immich-ml = "immich-machine-learning";
  };

  /*
    ── Stay awake when folded ────────────────────────────────────────
    Same defense-in-depth as pavilion (see comment there):
      1. logind lid handlers ignore
      2. systemd sleep/suspend/hibernate targets masked
      3. wifi power-save off via udev
      4. Intel iwlwifi `power_save=0` modprobe option (Aurora's NIC
         is the 7265 — Intel's default is power_save=1 which dropped
         the link on first fold test)
  */
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="wl*", RUN+="${pkgs.iw}/bin/iw dev %k set power_save off"
  '';
  boot.extraModprobeConfig = ''
    options iwlwifi power_save=0
  '';

  # ── Networking ─────────────────────────────────────────────────────
  networking.useDHCP = lib.mkDefault true;

  /*
    Wifi via iwd. No impermanence here, so /var/lib/iwd persists on
    the @root subvol — no /persist binds needed (unlike pavilion).
    SSID + PSK dropped at install time; rotate via
    `iwctl station wlp2s0 connect <SSID>`. See
    [[nixos-anywhere-first-install-gotchas]].
  */
  networking.wireless.iwd.enable = true;
  networking.wireless.enable = false;

  services.tailscale.useRoutingFeatures = lib.mkForce "none";

  /*
    Tailnet firewall: backend ports are opened by the `exposeOnTailnet`
    field on each `nori.lanRoutes.<X>` entry — pi's Caddy reaches the
    backend over tailnet. The lan-route generator filters by runsOn,
    so only the host that owns the backend opens the port.

    SSH (22) is opened by services.openssh.openFirewall (global, default
    true). Samba (445) is opened by modules/services/samba.nix on the
    tailnet interface. immich-machine-learning (3003) stays loopback-
    only — post-P11 immich-server is co-located here and reaches ML
    via 127.0.0.1:3003 (forced below).
  */

  /*
    ── NVIDIA (GTX 950M, Maxwell) ────────────────────────────────────
    Legacy 535-series driver is the last to support Maxwell. Wayland
    off because there's no display — aurora is headless. CUDA enabled
    for the ML workload.
  */
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = false;
    nvidiaSettings = false;
    open = false;
    powerManagement.enable = false;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_535;
  };

  /*
    CUDA available to userspace + containers. immich-ml uses ONNX
    runtime with CUDA execution provider when this is in place.
  */
  nixpkgs.config.cudaSupport = true;

  /*
    ── immich (full server + ML + database co-located) ──────────────
    Aurora hosts the canonical immich: server + microservices +
    postgres + redis + machine-learning all live here, the ML
    reachable over tailnet at port 3003.

    The shared immich.nix module assumes server-only on the importing
    host (with ML offloaded elsewhere), so it sets
    machine-learning.enable = false. Override on aurora — aurora IS the
    ML host. mkForce beats the module's default; mkForce + mkForce
    would conflict, so the module uses default priority on
    machine-learning.enable and aurora's mkForce wins.
  */
  services.immich.machine-learning = {
    enable = lib.mkForce true;
    environment.IMMICH_HOST = lib.mkForce "0.0.0.0";
  };
  # Server binds tailnet — pi's Caddy reaches over tailnet0 post-cutover.
  systemd.services.immich-server.environment.IMMICH_HOST = lib.mkForce "0.0.0.0";
  /*
    Module sets IMMICH_MACHINE_LEARNING_URL with mkForce to aurora's
    tailnetIp:3003 (correct for cross-host from workstation). On
    aurora itself the tailnet IP routes back through tailnet0 — works
    but loops over a network stack. mkOverride 49 beats the module's
    mkForce (50) and points at loopback directly.
  */
  systemd.services.immich-server.environment.IMMICH_MACHINE_LEARNING_URL =
    lib.mkOverride 49 "http://127.0.0.1:3003";

  # ── SSH ───────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = lib.mkForce "prohibit-password";
    };
  };

  /*
    Operator pubkey for both nori (interactive) and root (deploys).
    Same key as pavilion + other lab hosts. See
    [[nixos-anywhere-first-install-gotchas]] for the rationale on
    baking these into the host config rather than relying on ssh-copy-id.
  */
  users.users.nori.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgBC1J2CYrhdwFerwCa9GZD15I03vqS07bFtiYRl2FU nori-station@github"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgBC1J2CYrhdwFerwCa9GZD15I03vqS07bFtiYRl2FU nori-station@github"
  ];

  /*
    Console-fallback password — same TEMP placeholder pattern as
    pavilion. Operator rotates via `mkpasswd -m yescrypt`, paste,
    redeploy. Or sops-encrypt + hashedPasswordFile.
  */
  users.users.nori.hashedPassword = "$y$j9T$tpPHfhX/.CWM6TKcQThdq/$cfEGxBsEhlBcv3ulkVxNsHNyjrpHsYDPdTeTsOu/Vb7";

  # ── Posture assertions ────────────────────────────────────────────
  assertions = [
    {
      assertion = config.nori.hosts.${config.networking.hostName}.role == "workhorse";
      message =
        "aurora's role must be 'workhorse' in inventory/hosts.nix. "
        + "Aurora is the always-on family-vault workhorse; placement and "
        + "topology must agree before changing this role.";
    }
  ];
}
