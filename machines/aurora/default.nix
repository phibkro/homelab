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
# 1. Workstation's modules/server/immich.nix needs an env override
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
    #   modules/server/default.nix — no LAN service stack
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
  # Placeholder — the upstream services.immich.machine-learning option
  # may require the umbrella services.immich.enable. Verify on first
  # deploy; if the sub-option doesn't work standalone, fall back to a
  # hand-rolled systemd unit running the immich-machine-learning
  # container with --gpus all. Either way it should listen on
  # 0.0.0.0:3003 so workstation reaches it via tailnet.
  #
  # services.immich.machine-learning = {
  #   enable = true;
  #   host = "0.0.0.0";
  #   port = 3003;
  # };

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
