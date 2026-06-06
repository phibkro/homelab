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
# same 5060 Ti. Under heavy photo ingest (Immich's smart-search re-
# index or face-detection backfill), the model evict/reload thrash
# tanks ollama latency for the operator. Splitting immich-ml onto a
# dedicated GPU peer fixes that. The 950M's 2 GB VRAM is plenty for
# CLIP-ViT-B/32 (≈350 MB) + RetinaFace (≈250 MB) + Tesseract OCR
# (CPU-side), and its Maxwell-era CUDA is genuinely fast at batched
# inference even if it's a decade old.
#
# ── Posture ────────────────────────────────────────────────────────
# * Stateless from a backup perspective — immich's authoritative
#   state (DB, originals, embeddings) lives on workstation. What
#   aurora caches is just downloaded ML model weights, replaceable
#   on first run.
# * No impermanence — model weights are ~2 GB and re-downloading
#   every boot would be wasteful. Regular btrfs root.
# * No services exposed to LAN. immich-ml listens on tailnet only;
#   workstation's immich-server reaches it via tailnet ACL.
# * No claude-code, no operator GitHub credential. Operator's daily
#   driver stays on workstation.
#
# ── Open items (post-deploy) ───────────────────────────────────────
# 1. Workstation's modules/services/immich.nix needs an env override
#    to point at aurora:
#       IMMICH_MACHINE_LEARNING_URL=http://aurora.saola-matrix.ts.net:3003
#    plus disable services.immich.machine-learning.enable locally.
# 2. Verify the upstream services.immich.machine-learning sub-module
#    can run standalone (without the umbrella server). If not, fall
#    back to a custom systemd unit running the container directly.
# 3. NVIDIA driver: legacy 535-series for Maxwell. Verify CUDA
#    available to the ML container.
#
# Captured in [[nixos-anywhere-first-install-gotchas]] for the
# pre-deploy checklist.

{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.home-manager.nixosModules.home-manager

    ../../modules/common

    # Notably absent:
    #   modules/services/default.nix — no LAN service stack
    #   modules/desktop/default.nix — headless

    ./hardware.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    backupFileExtension = "hm-backup";
    users.nori.imports = [ ./home.nix ];
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

  # Wifi via iwd. Aurora's a laptop with no impermanence, so iwd
  # state in /var/lib/iwd persists naturally on the @root subvol —
  # no /persist binds needed (unlike pavilion). Captured Akkar PSK
  # gets dropped at install time; subsequent SSID changes can use
  # `iwctl station wlp2s0 connect <SSID>` interactively.
  #
  # Captured in [[nixos-anywhere-first-install-gotchas]] — this is
  # gap #1 from the pavilion lesson. Re-learned on aurora because I
  # forgot to apply the lesson to the sketch.
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
        # Override upstream's localhost default; need mkForce because
        # the upstream module sets the same key at the same priority.
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
  users.users.nori.hashedPassword =
    "$y$j9T$tpPHfhX/.CWM6TKcQThdq/$cfEGxBsEhlBcv3ulkVxNsHNyjrpHsYDPdTeTsOu/Vb7";

  # ── Posture assertions ────────────────────────────────────────────
  assertions = [
    {
      assertion = config.nori.hosts.${config.networking.hostName}.role == "workhorse";
      message =
        "aurora's role must be 'workhorse' in flake.nix identityFor "
        + "(currently classified workhorse despite minimal service "
        + "footprint — see header comment about the rule-of-three "
        + "trigger for a future `compute` role).";
    }
  ];
}
