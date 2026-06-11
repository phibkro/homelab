{
  config,
  lib,
  modulesPath,
  inputs,
  pkgs,
  ...
}:

{
  # pi is a Raspberry Pi 4 (8 GiB) appliance — DNS adblock,
  # observability redundancy (Gatus + ntfy probing workstation so
  # alerts still fire when station's down), Tailscale subnet
  # router + opt-in exit node, and eventually the local restic
  # backup target for fast restores.
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4

    # The aarch64 sd-image installer module gives us
    # `system.build.sdImage` so we can build a flashable .img on
    # workstation via aarch64 binfmt and dd it to the FIT, instead
    # of running an interactive installer.
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"

    ../../modules/common

    # Full service bundle. Post P2/P3 wrap + P1b route lift, importing
    # the bundle does NOT activate services — each module's body is
    # gated on `nori.services.<X>.enabled`. Routes are declared at
    # import time so pi's Caddy (when enabled below) gets the complete
    # `*.${nori.domain}` map without per-route stubs.
    ../../modules/services

    # Appliance-specialty modules that live outside the bundle (the
    # bundle covers what workstation runs; these are pi-side service
    # halves of the workhorse/appliance splits, plus pi's heartbeat).
    ../../modules/services/beszel/hub.nix
    ../../modules/services/ntfy/server.nix
    ../../modules/services/victorialogs/server.nix
    ../../modules/services/victoriametrics.nix
    ../../modules/services/heartbeat.nix

    ./hardware.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  # home-manager-as-NixOS-module wrapper. Same shape as
  # machines/workstation/default.nix; extract a shared snippet at the
  # third NixOS host (laptop NixOS would be the trigger).
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    backupFileExtension = "hm-backup";
    users.nori.imports = [ ./home.nix ];
  };

  # Service-placement registry. Pre-existing services (network appliance
  # + observability) plus the ADR-0003 entry-plane trio (Caddy +
  # Authelia + Blocky-authoritative now on pi). Workstation continues
  # to serve LAN traffic until the Tailscale DNS push order swap
  # (operator action) — both Caddys + Authelias run in parallel until
  # then, each holding their own LE wildcard cert for `*.${nori.domain}`.
  nori.services = {
    # Pre-existing pi services
    gatus.enable = true;
    beszel-hub.enable = true;
    beszel-agent.enable = true;
    ntfy-server.enable = true;
    ntfy-notify.enable = true;
    victorialogs-server.enable = true;
    victoriametrics.enable = true;
    heartbeat.enable = true;
    # ADR-0003 entry plane standup (P7). Blocky stays enabled below;
    # its role flips from "forwarder" to "self-hosted" so pi serves
    # the customDNS map directly (matches workstation's). Authelia
    # loads the same sops material as workstation's instance — both
    # accept logins for the same users + OIDC clients during parallel.
    blocky.enable = true;
    caddy.enable = true;
    authelia.enable = true;
  };

  # Blocky role: pre-P7 pi was a forwarder (delegated `*.${nori.domain}`
  # queries to workstation). Post-P7 pi is self-hosted (authoritative
  # for the customDNS map auto-generated from `nori.lanRoutes`).
  #
  # Pi's blocky still returns workstation's LAN IP (the default derived
  # `nori.lanIp`), so clients land on workstation's Caddy. Pi's Caddy
  # is standing by but receives no production traffic — backends bound
  # to 127.0.0.1 on workstation can't be proxied across the tailnet.
  # The lanIp override (and the matching Tailscale split-DNS flip to
  # pi) lands per-service as workstation services migrate to aurora /
  # rebind to 0.0.0.0 during P8/P12.
  nori.blocky.role = "self-hosted";

  # Pi-side backup target — the OneTouch on aurora via SFTP, same
  # repository as workstation reaches. The cross-cutting infrastructure
  # in modules/services/backup/restic.nix is gated workstation-only by
  # design (workstation holds the data those jobs back up); pi's
  # Caddy/Authelia state declares its own backups that target this
  # SFTP-to-aurora repo. Anti-write posture preserved: restic reads
  # local state, streams over SFTP to aurora.
  sops.secrets.restic-password = {
    owner = "root";
    mode = "0400";
  };
  sops.secrets.restic-ssh-key = {
    owner = "root";
    mode = "0400";
  };
  environment.etc."ssh/aurora_known_hosts".text = ''
    aurora.saola-matrix.ts.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnfMYRv1a3CGvnL0e82w/Z1RK7aOqS3k8JvMYbD8NET
  '';
  nori.backupTargets.onetouch = {
    repository = "sftp:restic@aurora.saola-matrix.ts.net:";
    description = "Pi → OneTouch via aurora SFTP. Same repo workstation pushes to; restic snapshots are content-addressed so per-host repos don't collide (each job writes to /<jobname>).";
    extraOptions = [
      "sftp.command='${pkgs.openssh}/bin/ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/ssh/aurora_known_hosts -i /run/secrets/restic-ssh-key restic@aurora.saola-matrix.ts.net -s sftp'"
    ];
  };

  # /var/backup tmpfiles for any Pattern C2 prepareCommand to write
  # into (e.g. authelia's sqlite VACUUM INTO target).
  systemd.tmpfiles.rules = [ "d /var/backup 0755 root root -" ];

  # networking.hostName injected from the registry key in flake.nix.
  networking.useDHCP = lib.mkDefault true;

  # Tailscale routing role — Pi advertises the LAN subnet + offers
  # exit-node service. Both opt-in per-device in the Tailscale admin
  # console after first auth. First-boot auth is manual (CLAUDE.md
  # gotcha: services.tailscale.authKeyFile via sops-nix is the
  # eventual path; for now: `sudo tailscale up --ssh
  # --advertise-routes=192.168.1.0/24 --advertise-exit-node
  # --hostname=pi`).
  services.tailscale.useRoutingFeatures = lib.mkForce "server";

  # Required for any tailscale node advertising routes.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Workaround for the modules-shrunk failure when using cache.garnix.io's
  # cached `linux-rpi` kernel. Garnix's CI builds the kernel with a
  # slightly different module set than what nixos-hardware/raspberry-pi-4
  # requests — specifically `dw-hdmi` (DesignWare HDMI) is missing from
  # the cached build, so the post-build module-shrinking step fails with
  # `modprobe: FATAL: Module dw-hdmi not found`.
  #
  # `allowMissingModules = true` (nixpkgs PR 375975, merged staging-next
  # 2025-05-16, in nixos-25.11) tells initrd to skip the strict modules
  # closure check. Trade-off: real missing-module regressions become
  # silent. Acceptable for an appliance-class Pi.
  #
  # Without this: build kernel locally (~60 min via aarch64 binfmt
  # emulation on workstation). With this: garnix cache hit, build
  # finishes in ~15 min total.
  boot.initrd.allowMissingModules = true;

  # ── Gatus: mutual-observability probes ───────────────────────────
  # Pi runs its own Gatus instance probing workstation's services.
  # Alerts go directly to ntfy.sh (not via station's local ntfy),
  # so the alert path survives station-down events. This is the load-
  # bearing piece — when station's Gatus hangs (the 2026-04-28
  # incident pattern), Pi's Gatus catches and alerts.
  #
  # No Caddy on Pi — exposeViaCaddy=false skips the lanRoutes.status
  # registration. If you ever need the web UI from elsewhere, reach
  # the port directly via tailnet (firewall opened below for tailnet
  # only).
  nori.gatus.exposeViaCaddy = false;

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    8082 # Gatus web UI on tailnet only
  ];

  # station-blocky-dns is the most important probe — catches the
  # userspace-CPU-starvation pattern (kernel alive, NIC ACKs ping, DNS
  # dead). LAN-side because `*.nori.lan` resolves to LAN IPs.
  # station-ssh is full host-down detection.
  # station-caddy confirms the *.nori.lan tier is serving (HTTP probe).
  # self-blocky-dns is the self-canary; if it fires, pi's DNS is dead.
  nori.gatusProbes = {
    station-blocky-dns.url = "tcp://${config.nori.lanIp}:53";
    station-ssh.url = "tcp://${config.nori.lanIp}:22";
    station-caddy = {
      url = "https://status.${config.nori.domain}";
      interval = "120s";
      conditions = [ "[STATUS] == 200" ];
    };
    self-blocky-dns.url = "tcp://127.0.0.1:53";
  };

}
