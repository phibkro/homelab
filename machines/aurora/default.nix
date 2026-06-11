{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:

# aurora — retired Asus N552V (i7-6700HQ, 12 GB RAM, GTX 950M
# Maxwell, dead battery). Single-role: immich machine-learning
# offload host so workstation's 5060 Ti stays dedicated to ollama.
#
# ── Why it exists ──────────────────────────────────────────────────
# Workstation runs ollama AND immich's CLIP/face/OCR pipeline on the
# same 5060 Ti. Heavy photo ingest (smart-search re-index, face-
# detection backfill) evict/reload-thrashes ollama and tanks
# operator latency. The 950M's 2 GB VRAM fits CLIP-ViT-B/32 (~350 MB)
# + RetinaFace (~250 MB) with Tesseract OCR on CPU, and Maxwell CUDA
# is still fast at batched inference.
#
# ── Posture ────────────────────────────────────────────────────────
# * Stateless from a backup perspective — immich's authoritative
#   state (DB, originals, embeddings) lives on workstation. Aurora
#   only caches downloaded ML weights, replaceable on first run.
# * No impermanence — weights are ~2 GB; re-downloading every boot
#   wastes bandwidth + startup. Regular btrfs root.
# * No services exposed to LAN. immich-ml listens on tailnet only;
#   workstation's immich-server reaches it via tailnet ACL.
# * No claude-code, no operator GitHub credential. Operator's daily
#   driver stays on workstation.

{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.home-manager.nixosModules.home-manager

    ../../modules/common

    # Per-process RSS + system metrics → pi VictoriaMetrics. Imported
    # file-by-file (not the whole services/ bundle) since aurora runs
    # only immich-machine-learning. PyTorch RSS is the known leak shape.
    ../../modules/services/node-exporter.nix
    ../../modules/services/nvidia-gpu-exporter.nix

    # Restic backup target: chrooted SFTP-only user for remote
    # restic clients pushing to /mnt/backup. Pairs with the
    # disko-onetouch entry below; both arrived 2026-06-11 when the
    # OneTouch HDD physically moved from workstation. See
    # docs/superpowers/plans/2026-06-11-aurora-migration.md § P13.
    ../../modules/services/backup/restic-target.nix

    # Notably absent:
    #   modules/services/default.nix — no LAN service stack
    #   modules/desktop/default.nix — headless

    ./hardware.nix
    ./disko-onetouch.nix
    ./disko-family.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    backupFileExtension = "hm-backup";
    users.nori.imports = [ ./home.nix ];
  };

  # Service-placement registry (aurora migration P3). Reproduces today's
  # aurora activation set — node-exporter + nvidia-gpu-exporter (the
  # immich-ml leak watch from the start), plus the restic-target SFTP
  # user landed during P13. Family-tier services arrive at P12 cutover.
  nori.services = {
    node-exporter.enable = true;
    nvidia-gpu-exporter.enable = true;
    restic-target.enable = true;
  };

  # ── Boot ───────────────────────────────────────────────────────────
  # 2016 laptop with UEFI — assume systemd-boot. If first boot reveals
  # legacy BIOS, flip to GRUB (see machines/pavilion/default.nix for
  # the BIOS-mode shape).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # MOTD additions on top of the universal core (modules/effects/
  # rust-motd.nix) — iwd is laptop-specific, immich-ml is aurora's
  # reason for existing.
  programs.rust-motd.settings.service_status = {
    iwd = "iwd";
    immich-ml = "immich-machine-learning";
  };

  # ── Stay awake when folded ────────────────────────────────────────
  # Same defense-in-depth as pavilion (see comment there):
  #   1. logind lid handlers ignore
  #   2. systemd sleep/suspend/hibernate targets masked
  #   3. wifi power-save off via udev
  #   4. Intel iwlwifi `power_save=0` modprobe option (Aurora's NIC
  #      is the 7265 — Intel's default is power_save=1 which dropped
  #      the link on first fold test)
  services.logind = {
    lidSwitch = "ignore";
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
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

  # Wifi via iwd. No impermanence here, so /var/lib/iwd persists on
  # the @root subvol — no /persist binds needed (unlike pavilion).
  # SSID + PSK dropped at install time; rotate via
  # `iwctl station wlp2s0 connect <SSID>`. See
  # [[nixos-anywhere-first-install-gotchas]].
  networking.wireless.iwd.enable = true;
  networking.wireless.enable = false;

  services.tailscale.useRoutingFeatures = lib.mkForce "none";

  # Tailnet firewall — operator SSH inbound only by default. immich-ml
  # listens on 3003; opened to tailnet here for workstation's
  # immich-server to reach.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    22 # SSH
    3003 # immich-machine-learning
  ];

  # ── NVIDIA (GTX 950M, Maxwell) ────────────────────────────────────
  # Legacy 535-series driver is the last to support Maxwell. Wayland
  # off because there's no display — aurora is headless. CUDA enabled
  # for the ML workload.
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = false;
    nvidiaSettings = false;
    open = false;
    powerManagement.enable = false;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_535;
  };

  # CUDA available to userspace + containers. immich-ml uses ONNX
  # runtime with CUDA execution provider when this is in place.
  nixpkgs.config.cudaSupport = true;

  # ── immich machine-learning (the actual reason this host exists) ──
  # The upstream services.immich module gates everything on
  # services.immich.enable. To run *only* ML on aurora we enable the
  # umbrella but turn off the local DB + redis (immich-server can't
  # work without them; we don't need server-side here anyway) and
  # force-disable the server + microservices units which would
  # otherwise crash-loop trying to connect to a missing postgres.
  #
  # IMMICH_HOST = "0.0.0.0" rebinds the ML listener from localhost so
  # workstation's immich-server can reach it over tailnet at
  # http://aurora.saola-matrix.ts.net:3003 (firewall rule above
  # already opens this port).
  services.immich = {
    enable = true;
    database.enable = false; # workstation hosts the canonical DB
    redis.enable = false; # ditto
    machine-learning = {
      enable = true;
      environment = {
        IMMICH_HOST = lib.mkForce "0.0.0.0";
      };
    };
    accelerationDevices = config.nori.gpu.nvidiaDevices;
  };

  # Aurora is ML-only — kill the server + microservices units so they
  # don't restart-loop trying to reach a postgres that isn't there.
  systemd.services.immich-server.enable = lib.mkForce false;
  systemd.services.immich-microservices.enable = lib.mkForce false;

  # ── SSH ───────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = lib.mkForce "prohibit-password";
    };
  };

  # Operator pubkey for both nori (interactive) and root (deploys).
  # Same key as pavilion + other lab hosts. See
  # [[nixos-anywhere-first-install-gotchas]] for the rationale on
  # baking these into the host config rather than relying on ssh-copy-id.
  users.users.nori.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgBC1J2CYrhdwFerwCa9GZD15I03vqS07bFtiYRl2FU nori-station@github"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgBC1J2CYrhdwFerwCa9GZD15I03vqS07bFtiYRl2FU nori-station@github"
  ];

  # Console-fallback password — same TEMP placeholder pattern as
  # pavilion. Operator rotates via `mkpasswd -m yescrypt`, paste,
  # redeploy. Or sops-encrypt + hashedPasswordFile.
  users.users.nori.hashedPassword = "$y$j9T$tpPHfhX/.CWM6TKcQThdq/$cfEGxBsEhlBcv3ulkVxNsHNyjrpHsYDPdTeTsOu/Vb7";

  # ── Posture assertions ────────────────────────────────────────────
  assertions = [
    {
      assertion = config.nori.hosts.${config.networking.hostName}.role == "workhorse";
      message =
        "aurora's role must be 'workhorse' in flake.nix identityFor. "
        + "(Currently classified workhorse despite the single-service "
        + "footprint; promote to a dedicated `compute` role on the "
        + "third single-GPU-peer host — rule of three.)";
    }
  ];
}
