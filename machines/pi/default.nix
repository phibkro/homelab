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
    ../../modules/infra/observability/beszel/hub.nix
    ../../modules/infra/observability/ntfy/server.nix
    ../../modules/infra/observability/victorialogs/server.nix
    ../../modules/infra/observability/victoriametrics.nix
    ../../modules/infra/observability/heartbeat.nix

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

  # Pi runs the network-appliance + observability set AND the HTTP
  # entry-plane trio (Caddy + Authelia + Blocky-authoritative) per
  # ADR-0003. Pi's Caddy holds an LE wildcard cert for `*.${nori.domain}`
  # — same as workstation's. Which Caddy clients actually hit is
  # decided by `nori.lanIp` (today: workstation; post-cutover: pi).
  nori.services = {
    gatus.enable = true;
    beszel-hub.enable = true;
    beszel-agent.enable = true;
    ntfy-server.enable = true;
    ntfy-notify.enable = true;
    victorialogs-server.enable = true;
    victoriametrics.enable = true;
    heartbeat.enable = true;
    blocky.enable = true;
    caddy.enable = true;
    authelia.enable = true;
  };

  # Blocky authoritative on pi: serves the customDNS map derived from
  # `nori.lanRoutes` directly, rather than forwarding to workstation.
  nori.blocky.role = "self-hosted";

  # Pi → OneTouch via aurora SFTP. Restic reads pi's local state
  # (Caddy + Authelia DB) and streams over SFTP — preserves pi's
  # anti-write posture (the SD card stays read-mostly).
  # `modules/infra/backup/restic.nix` is workstation-only by data
  # ownership; pi declares its own target + per-service backups here.
  #
  # Path prefix `/pi/` separates pi's snapshots from workstation's so
  # the two hosts never contend on the same restic repo lock — caddy
  # and authelia run on both, and a shared `:/<jobname>` namespace
  # races on whoever takes the exclusive lock first. With `/pi/`
  # prefix, pi writes to `/mnt/backup/pi/<jobname>` on aurora while
  # workstation keeps writing to `/mnt/backup/<jobname>`.
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
    repository = "sftp:restic@aurora.saola-matrix.ts.net:/pi";
    description = "Pi → OneTouch via aurora SFTP, scoped under /pi/ so pi's snapshots don't collide with workstation's on the shared chroot. Each job writes to /mnt/backup/pi/<jobname> on aurora.";
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

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    8082 # Gatus web UI on tailnet only
  ];

  # wakeonlan on PATH so the operator can WoL workstation from a phone
  # SSH session into pi (Termius snippet `wakeonlan <mac>`). Sends a
  # UDP magic packet (port 9), so no sudo or raw-socket cap needed.
  # See machines/workstation/hardware.nix § Wake-on-LAN for the
  # receiving side.
  environment.systemPackages = [ pkgs.wakeonlan ];

  # Tailnet appliance DNS interception — chromecast hardcodes 8.8.8.8
  # at the app layer and ignores DHCP + Tailscale's DNS push. Pi is its
  # exit node, so we DNAT outgoing :53 to Blocky here. MUST stay in sync
  # with tag:appliance assignment in the Tailscale ACL — same trust
  # boundary at two layers. See modules/effects/tailnet-appliance.nix
  # for the architectural-compromise note.
  nori.tailnet.appliances.chromecast = {
    tailnetIp = "100.94.135.114";
    interceptedAt = "pi";
  };

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
    aurora-ssh.url = "tcp://${config.nori.hosts.aurora.tailnetIp}:22";
    aurora-samba.url = "tcp://${config.nori.hosts.aurora.tailnetIp}:445";
  };

}
