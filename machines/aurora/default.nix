{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:

/**
  aurora — retired Asus N552V (i7-6700HQ, 12 GB RAM, GTX 950M
  Maxwell, dead battery). Single-role: immich machine-learning
  offload host so workstation's 5060 Ti stays dedicated to ollama.

  ── Why it exists ──────────────────────────────────────────────────
  Workstation runs ollama AND immich's CLIP/face/OCR pipeline on the
  same 5060 Ti. Heavy photo ingest (smart-search re-index, face-
  detection backfill) evict/reload-thrashes ollama and tanks
  operator latency. The 950M's 2 GB VRAM fits CLIP-ViT-B/32 (~350 MB)
  + RetinaFace (~250 MB) with Tesseract OCR on CPU, and Maxwell CUDA
  is still fast at batched inference.

  ── Posture ────────────────────────────────────────────────────────
  * Stateless from a backup perspective — immich's authoritative
    state (DB, originals, embeddings) lives on workstation. Aurora
    only caches downloaded ML weights, replaceable on first run.
  * No impermanence — weights are ~2 GB; re-downloading every boot
    wastes bandwidth + startup. Regular btrfs root.
  * No services exposed to LAN. immich-ml listens on tailnet only;
    workstation's immich-server reaches it via tailnet ACL.
  * No claude-code, no operator GitHub credential. Operator's daily
    driver stays on workstation.
*/

{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.home-manager.nixosModules.home-manager

    ../../modules/common

    /*
      Full services bundle. Importing does NOT activate services —
      each module's body is gated on `nori.services.<X>.enabled`,
      while routes are declared unconditionally. Enabling a service
      on aurora is a one-line edit per service (see `nori.services`
      below).
    */
    ../../modules/services

    /*
      Aurora-only specialty: chrooted SFTP backup target. Sits outside
      the bundle because it's not a user-facing service. Pairs with the
      disko-onetouch entry below; both arrived 2026-06-11 when the
      OneTouch HDD physically moved from workstation. See
      docs/plans/2026-06-11-aurora-migration.md § P13.
    */
    ../../modules/infra/backup/restic-target.nix

    # Notably absent:
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

  /*
    Service-placement registry. Pre-existing aurora services + the
    ADR-0002 P8 family-tier services standing up empty. Per the
    ADR-0003 addendum, runsOn (per route) stays at "workstation" until
    state is migrated and the backend is bound for cross-host proxy.
    Aurora's family-tier services initialize empty databases here; the
    operator runs the state migration (dump on workstation, sftp,
    restore on aurora) before flipping runsOn + Tailscale split-DNS.
  */
  nori.services = {
    node-exporter.enable = true;
    nvidia-gpu-exporter.enable = true;
    restic-target.enable = true;
    ntfy-notify.enable = true; # OnFailure → notify@ alerts for aurora-side units
    beszel-agent.enable = true; # high-level metrics → pi's Beszel hub

    /*
      P8 family-tier — small, sqlite-only services standing up empty.
      State migration + cutover are operator-driven per service; see
      the runbook in the P8 bellwether commit (e76907b). Postgres-
      backed services (immich, miniflux) are deferred — each is its
      own data + bootstrap exercise.
    */
    vaultwarden.enable = true; # bellwether
    radicale.enable = true; # CalDAV / CardDAV (sqlite)
    calibre-web.enable = true; # books (sqlite + library/books read)
    komga.enable = true; # comics (sqlite + library/comics read)
    glance.enable = true; # dashboard (stateless, reads lanRoutes)
    heim.enable = true; # operator portfolio (stateless serve, github build)
    immich.enable = true; # photos (postgres + redis + ML co-located)
    miniflux.enable = true; # RSS reader (postgres — shares immich's instance)
    filmder.enable = true; # personal-app (stateless serve, github build)
    grafana.enable = true; # observability frontend (sessions ephemeral; pi VM/logs over tailnet)
    samba.enable = true; # /mnt/family/* shares for family bookmarks
    navidrome.enable = true; # music (sqlite + library/music read)
    btrbk-replication.enable = true; # P15 — nightly send to workstation MP510
    syncthing.enable = true; # phone-to-library music sync (SpotiFlac path)
  };

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
    target declared in modules/infra/backup/restic-target.nix.
  */
  sops.secrets.restic-password = {
    owner = "root";
    mode = "0400";
  };
  nori.backupTargets.onetouch = {
    repository = "/mnt/backup";
    description = "Aurora-local OneTouch HDD (P13 dest). Aurora's own restic backups write here directly; remote hosts reach the same drive via SFTP per restic-target.nix.";
  };
  /*
    Aurora-side tmpfiles:
     - /var/backup for Pattern C2 prepareCommands (vaultwarden's sqlite
       VACUUM INTO, etc.).
     - /mnt/family/library/{books,comics} owned by `media` group so
       calibre-web + komga can write their initial empty-library state
       (each runs as its own user, both join `media`). The library
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
    "d /mnt/family/library/music      02775 root  media -"
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
    tmpfiles above. Mirrors machines/workstation/default.nix:53. Without
    this, syncthing logs `mkdir /mnt/family/library/<X>/.stfolder:
    permission denied` and the folder fails initial scan.
  */
  users.users.nori.extraGroups = [ "media" ];

  /*
    ── Boot ───────────────────────────────────────────────────────────
    2016 laptop with UEFI — assume systemd-boot. If first boot reveals
    legacy BIOS, flip to GRUB (see machines/pavilion/default.nix for
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
        "aurora's role must be 'workhorse' in flake.nix identityFor. "
        + "(Currently classified workhorse despite the single-service "
        + "footprint; promote to a dedicated `compute` role on the "
        + "third single-GPU-peer host — rule of three.)";
    }
  ];
}
