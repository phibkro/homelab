{
  config,
  lib,
  pkgs,
  modulesPath,
  inputs,
  ...
}:

{
  # pi is a Raspberry Pi 4 (8 GiB) appliance — DNS adblock,
  # observability redundancy (Gatus + ntfy probing workstation so
  # alerts still fire when station's down), Tailscale subnet
  # router + opt-in exit node, and eventually the local restic
  # backup target for fast restores.
  #
  # Per the "flat imports" decision (CLAUDE.md), this host does NOT
  # import modules/server/default.nix (the workstation bundle).
  # Pi-specific service modules will be added file-by-file once they're
  # refactored to be role-parametric.
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4

    # The aarch64 sd-image installer module gives us
    # `system.build.sdImage` so we can build a flashable .img on
    # workstation via aarch64 binfmt and dd it to the FIT, instead
    # of running an interactive installer.
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"

    ../../modules/common

    # Pi-specific service modules — flat imports per CLAUDE.md
    # "flat imports first." NOT modules/server/default.nix; just the
    # specific files Pi needs.
    ../../modules/server/blocky.nix
    ../../modules/server/gatus.nix

    # Beszel: Pi runs both the hub (collects metrics) and an agent
    # (reports its own metrics). Station only imports agent.nix. The
    # hub-host is intentionally the appliance side so it survives
    # station outages (forensics use case).
    ../../modules/server/beszel/hub.nix
    ../../modules/server/beszel/agent.nix

    # ntfy: Pi runs the local server (for future internal-only alerts);
    # both hosts import notify.nix for the OnFailure → ntfy.sh template.
    # Same workhorse/appliance split as beszel — alert plane lives on
    # the appliance so it survives station outages.
    ../../modules/server/ntfy/server.nix
    ../../modules/server/ntfy/notify.nix

    ./hardware.nix
    ../../home/pi.nix
  ];

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

  # ── Caddy local CA trust ─────────────────────────────────────────
  # Pi's Gatus probes station's services via https://*.nori.lan,
  # which terminates TLS using Caddy's internal CA. Trust that CA
  # at the system level so Go-stdlib HTTPS clients (Gatus, curl,
  # etc.) verify successfully without per-call --insecure flags.
  # Same pattern station uses (see modules/server/caddy.nix).
  security.pki.certificateFiles = [ ../../modules/server/caddy-local-ca.crt ];

  # ── Blocky: forwarder mode ───────────────────────────────────────
  # Pi serves DNS + ad blocking to LAN clients. *.nori.lan queries
  # get conditional-forwarded to workstation's Blocky (which has
  # the actual map auto-generated from nori.lanRoutes). This means
  # adding a new service on station doesn't require any Pi-side
  # change — Pi just delegates the suffix.
  nori.blocky.role = "forwarder";

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

  services.gatus.settings.endpoints = [
    {
      # Station's Blocky on LAN IP — the most important probe.
      # Catches the userspace-CPU-starvation pattern (kernel still
      # alive, NIC ACKs ping, but DNS is dead). LAN-side because
      # `*.nori.lan` resolution now resolves to LAN IPs (see
      # modules/effects/lan-route.nix nori.lanIp); tailnet-side death
      # is a separate concern that doesn't break user-visible service.
      name = "station-blocky-dns";
      url = "tcp://${config.nori.lanIp}:53";
      interval = "60s";
      conditions = [ "[CONNECTED] == true" ];
      alerts = [
        {
          type = "ntfy";
          failure-threshold = 3;
          send-on-resolved = true;
        }
      ];
    }
    {
      # Station's SSH — full host-down detection (sshd dead = host
      # dead from the user's perspective even if some daemons live).
      name = "station-ssh";
      url = "tcp://${config.nori.lanIp}:22";
      interval = "60s";
      conditions = [ "[CONNECTED] == true" ];
      alerts = [
        {
          type = "ntfy";
          failure-threshold = 3;
          send-on-resolved = true;
        }
      ];
    }
    {
      # Station's Caddy on HTTPS — confirms the *.nori.lan tier is
      # serving. Probes the well-known status.nori.lan route.
      name = "station-caddy";
      url = "https://status.nori.lan";
      interval = "120s";
      conditions = [ "[STATUS] == 200" ];
      alerts = [
        {
          type = "ntfy";
          failure-threshold = 3;
          send-on-resolved = true;
        }
      ];
    }
    {
      # Self-probe — Pi's own Blocky on localhost. If this fires,
      # Pi's DNS is broken and station's Gatus should also be alerting
      # (when station gains a Pi-side probe).
      name = "self-blocky-dns";
      url = "tcp://127.0.0.1:53";
      interval = "60s";
      conditions = [ "[CONNECTED] == true" ];
      alerts = [
        {
          type = "ntfy";
          failure-threshold = 3;
          send-on-resolved = true;
        }
      ];
    }
  ];

}
