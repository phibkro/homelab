{
  config,
  lib,
  pkgs,
  modulesPath,
  inputs,
  ...
}:

{
  # nori-pi is a Raspberry Pi 4 (8 GiB) appliance — DNS adblock,
  # observability redundancy (Gatus + ntfy probing nori-station so
  # alerts still fire when station's down), Tailscale subnet
  # router + opt-in exit node, and eventually the local restic
  # backup target for fast restores.
  #
  # Per the "flat imports" decision (CLAUDE.md), this host does NOT
  # import modules/server/default.nix (the nori-station bundle).
  # Pi-specific service modules will be added file-by-file once they're
  # refactored to be role-parametric.
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4

    # The aarch64 sd-image installer module gives us
    # `system.build.sdImage` so we can build a flashable .img on
    # nori-station via aarch64 binfmt and dd it to the FIT, instead
    # of running an interactive installer.
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"

    ../../modules/common

    # Pi-specific service modules — flat imports per CLAUDE.md
    # "flat imports first." NOT modules/server/default.nix; just the
    # specific files Pi needs.
    ../../modules/server/blocky.nix
    ../../modules/server/gatus.nix

    ./hardware.nix
  ];

  networking.hostName = "nori-pi";
  networking.useDHCP = lib.mkDefault true;

  # Tailscale routing role — Pi advertises the LAN subnet + offers
  # exit-node service. Both opt-in per-device in the Tailscale admin
  # console after first auth. First-boot auth is manual (CLAUDE.md
  # gotcha: services.tailscale.authKeyFile via sops-nix is the
  # eventual path; for now: `sudo tailscale up --ssh
  # --advertise-routes=192.168.1.0/24 --advertise-exit-node
  # --hostname=nori-pi`).
  services.tailscale.useRoutingFeatures = lib.mkForce "server";

  # Required for any tailscale node advertising routes.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # ── Blocky: forwarder mode ───────────────────────────────────────
  # Pi serves DNS + ad blocking to LAN clients. *.nori.lan queries
  # get conditional-forwarded to nori-station's Blocky (which has
  # the actual map auto-generated from nori.lanRoutes). This means
  # adding a new service on station doesn't require any Pi-side
  # change — Pi just delegates the suffix.
  nori.blocky.role = "forwarder";

  # ── Gatus: mutual-observability probes ───────────────────────────
  # Pi runs its own Gatus instance probing nori-station's services.
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
      # Station's Blocky on tailnet IP — the most important probe.
      # Catches the userspace-CPU-starvation pattern (kernel still
      # alive, NIC ACKs ping, but DNS is dead).
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

  # ── Beszel agent: ships metrics to station's hub ─────────────────
  # Hub stays station-only (per "station-only" decision in CLAUDE.md
  # outstanding). Pi just runs the agent. The agent key needs to be
  # generated via the hub's web UI on first boot of Pi:
  #   1. Boot Pi, ensure tailscale connectivity
  #   2. https://metrics.nori.lan → Add System → "nori-pi" →
  #      host=<pi-tailnet-ip>, port=45876
  #   3. Hub generates the KEY=ssh-ed25519 ... line
  #   4. `sops secrets/secrets.yaml` → add as block-string:
  #        beszel-agent-key-nori-pi: |
  #          KEY=ssh-ed25519 AAAA...
  #   5. Re-encrypt for Pi (after Pi's age key is in .sops.yaml)
  #   6. Deploy. Hub sees Pi within ~30s.
  #
  # Disabled until secret exists — uncomment after step 5 above.
  # sops.secrets.beszel-agent-key-nori-pi = { mode = "0400"; };
  # services.beszel.agent = {
  #   enable = true;
  #   environmentFile = config.sops.secrets.beszel-agent-key-nori-pi.path;
  # };
}
