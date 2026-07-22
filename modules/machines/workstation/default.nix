{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  /**
    workstation is a server + a desktop. Each `modules/<concern>`
    import is one role this machine plays; the host is the sum of
    its concerns plus its physical hardware.
  */
  imports = [
    inputs.disko.nixosModules.disko

    ./hardware.nix
    ./disko.nix
    ./disko-media.nix
    ./disko-mp510.nix
  ];

  # networking.hostName injected from the registry key in flake.nix.
  networking.useDHCP = lib.mkDefault true;

  /*
    Add the operator user to the `media` group so shell access + any
    service running as `nori` (Syncthing's binds, e.g.) can write to
    /mnt/media/{downloads,library} which are owned root:media 02775
    by arr/shared.nix tmpfiles. The group itself is defined in
    arr/shared.nix — workstation-only, hence the workstation-host-
    scope here rather than common/users.nix (which Pi also reads).
  */
  users.users.nori.extraGroups = [ "media" ];

  /*
    ntfy topic for agent-attention pushes (home-manager: nori.agentNotify).
    Separate secret from the infra `ntfy-channel` so "an agent halted and
    needs you" is its own phone subscription + priority, not mixed with
    "a service is down". owner nori + mode 0400: only the operator's
    interactive agents read it (agent-notify runs as nori), unlike the
    world-readable infra channel that system alert units share.
  */
  sops.secrets.ntfy-agents-channel = {
    owner = "nori";
    mode = "0400";
  };

  # The agents channel + route: agent-notify emits `--audience agents`,
  # this maps it to the dedicated topic. Defined here (not in the shared
  # home module) because the secret + nori-alert live at the system layer
  # on the host that runs the fleet.
  nori.alerts.channels.agents.topicSecret = config.sops.secrets.ntfy-agents-channel.path;
  nori.alerts.routes.agents = [ "agents" ];

  /*
    Fix-agent: ARMED on backup verification + snapshot units. A real failure
    (surviving the recovery window) OnFailure-dispatches a boxed agent that
    diagnoses, fixes on an origin/main clone, validates with `nix flake check`,
    and opens a PR — PR-only, never deploys. Dry-run validated 2026-07-18 (it
    found + fixed the SFTP restic-check bug this same PR carries).
    Design: docs/specs/2026-07-18-agent-fix-on-failure-design.md.
  */
  nori.agentFix.enable = true;
  nori.agentFix.units = [
    "restic-check-weekly"
    "restic-check-monthly"
    "btrbk-root"
    "btrbk-media"
  ];

  /*
    CI-only stub for davinci-resolve. It's unfree → not on cache.nixos.org →
    every `nix flake check` in CI rebuilds a multi-GB binary repackage
    (fetch + autoPatchelf over GBs, ~40 min), right at the GitHub runner's
    disk/time limit — the 2026-07-18 SIGTERM (143) that killed a PR run.

    Pure eval sees getEnv "" → the real package, so local `just rebuild` and
    local `nix flake check` are UNAFFECTED. Only CI opts in, via
    `HOMELAB_CI=1 nix flake check --impure` (see .github/workflows/check.yml):
    then davinci-resolve becomes a no-op shim, the workstation toplevel builds
    in minutes, and CI keeps build-coverage of everything except this one
    proprietary blob. Tradeoff: the impurity is contained to the CI flag; the
    only lost coverage is "does davinci's binary repackage build", which is a
    stable upstream concern local rebuild catches before deploy.
  */
  nixpkgs.overlays = lib.optionals (builtins.getEnv "HOMELAB_CI" == "1") [
    (_final: prev: {
      davinci-resolve = prev.writeShellScriptBin "davinci-resolve" "exit 0";
    })
  ];

  /*
    Waydroid — Android (LineageOS) in an LXC container, integrated with
    the Wayland (Hyprland) session. Runs Android-only apps (Symfonium, and
    anything else gated behind Google-Play licensing) at near-native speed
    — a container against the host kernel, not a full QEMU emulator. The
    module wires the `binder_linux` device + the waydroid-container service.

    Runtime setup AFTER this lands (not declarable — Android image state):
      sudo waydroid init -s GAPPS        # LineageOS image WITH Google Play
      # NVIDIA (RTX 5060 Ti) has no Waydroid GL path → force software render:
      #   waydroid prop set ro.hardware.gralloc default
      # then device-certify the GSF id at google.com/android/uncertified,
      # sign into Google, install the app. See the runbook.
  */
  virtualisation.waydroid.enable = true;
  # The module defaults to pkgs.waydroid (iptables-LEGACY net script) because
  # networking.nftables.enable is false here. But this kernel ships no legacy
  # `ip_tables` module — the host firewall already runs on the nf_tables backend
  # (iptables-nft). So force the nftables waydroid variant, whose net script uses
  # `nft` directly; its NAT/forward rules live in their own table and coexist with
  # the iptables-nft firewall. Avoids flipping the whole host to nftables.enable.
  #
  # ...and patch its dnsmasq to DHCP-only (`--port=0`): Blocky already wildcard-
  # binds 0.0.0.0:53 on this host, so waydroid's own dnsmasq can't grab
  # 192.168.240.1:53 ("address already in use"). Dropping dnsmasq's DNS frees
  # that bind; Blocky then answers the Android container on the bridge IP (verified
  # it serves the 240.x subnet), so DHCP just hands out 240.1 as the resolver via
  # option 6. Android gets DNS — with ad-blocking — and no host DNS is disturbed.
  virtualisation.waydroid.package = pkgs.waydroid-nftables.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      net="$out/lib/waydroid/data/scripts/.waydroid-net.sh-wrapped"
      substituteInPlace "$net" \
        --replace-fail \
          '--listen-address ''${LXC_ADDR} --dhcp-range ''${LXC_DHCP_RANGE}' \
          '--port=0 --dhcp-option=6,''${LXC_ADDR} --listen-address ''${LXC_ADDR} --dhcp-range ''${LXC_DHCP_RANGE}'
    '';
  });

  # Let the Waydroid Android container reach this host's Samba over its bridge,
  # so Symfonium reads the local music library via SMB (→ 192.168.240.1, share
  # `media`, path library/music). Android's FUSE storage can't cross a
  # bind-mount of the library into /storage, so SMB over the bridge is the path.
  # Scoped to waydroid0; Samba's hosts-allow gates the 240.x subnet (samba.nix).
  networking.firewall.interfaces.waydroid0.allowedTCPPorts = [ 445 ];

  # FLAC ingest timer. The phone pushes new lossless
  # FLAC into a transient Syncthing staging dir; this MOVEs complete, stable
  # files into the master library and deletes the staging copy (a separate
  # Syncthing folder propagates that delete back to the phone, freeing its FLAC).
  # Staging is deliberately OUTSIDE ${library}: no backup intent, and the phone
  # can never reach the master. See docs/runbooks/music-flac-ingest.md.
  nori.musicIngest = {
    stagingPath = "/mnt/media/staging/music-flac";
  };

  # Pre-create the staging tree. /mnt/media is root:root, so Syncthing (runs as
  # nori, in `media`) can't mkdir under it. root:media 2775 (setgid) lets both
  # Syncthing receive into it and the music-ingest user delete from it; new
  # files inherit the media group.
  systemd.tmpfiles.rules = [
    "d /mnt/media/staging            0755 root root  - -"
    "d /mnt/media/staging/music-flac 2775 root media - -"
  ];

  # Syncthing's sandbox (nori.harden) binds only library + downloads by default,
  # so the new staging dir is invisible inside the service namespace ("folder
  # path missing"). Bind it RW so Syncthing can receive the phone's FLAC into it
  # and propagate the ingest's deletes back. music-ingest reaches it via its own
  # harden binds.
  nori.harden.syncthing.binds = [ "/mnt/media/staging/music-flac" ];

  # Syncthing creates received dirs with its process umask; the default 0022
  # leaves them group-unwritable (drwxr-sr-x), so the media-group music-ingest
  # user can't unlink files from Syncthing-created staging subdirs (unlink needs
  # WRITE on the parent dir, not the file). 0002 → group-writable trees, matching
  # the media-group collaboration model (the library is already root:media 02775).
  systemd.services.syncthing.serviceConfig.UMask = "0002";

  /*
    Defensive cap on user@1000.service. Calibrated against the
    2026-06-08 global-OOM event: a leak inside the user session climbed
    to 26.2 GiB RSS + 21.5 GiB swap peak in 3h, exhausted total memory
    (32 GiB RAM + 16 GiB zram + 8 GiB disk swap), and the kernel OOM
    killer fired with CONSTRAINT_NONE — killing lua-language-server
    inside the Hyprland session and cascading user@1000 to deactivate,
    taking down the entire desktop.

    MemoryHigh = soft cap, throttles via swap pressure when reached.
    MemoryMax  = hard cap, OOM-kills inside the unit instead of system-
                 wide. With the cap, a runaway desktop kills itself and
                 system services (sshd, caddy, blocky, tailscaled) stay
                 alive — recoverable from a TTY or remote SSH.

    Numbers leave ≥4 GiB physical + 8 GiB swap headroom for kernel,
    system slice, and a brief grace for terminating processes. Track
    the actual session footprint in process-exporter (ROADMAP #45) and
    tighten if normal heavy use stays well under.

    SECOND CALIBRATION — the 2026-07-09 thrash-freeze: these caps alone
    did NOT protect against it, because they bound RESIDENT memory only.
    A concurrent agent fleet (7+ Claude Code sessions) reached ~39 GiB
    working set; MemoryHigh throttled the slice by reclaiming into swap,
    the 32 GiB swapfile (grown since 2026-06-08) absorbed everything, so
    memory.current never crossed MemoryMax and NOTHING was killed —
    instead swap filled to 47.6/47.6 GiB, PSI memory full-stall hit 22%,
    and the desktop live-locked until a power-button shutdown. The two
    additions close both halves of that gap:

    MemorySwapMax = bounds the slice's SWAP separately (cgroup-v2
                    memory.swap.max). When the slice has swapped 16 GiB,
                    reclaim can no longer spill; resident then climbs to
                    MemoryMax and the kernel kills INSIDE the slice —
                    the same contained-kill story as before, restored.
                    Worst-case slice footprint: 28 + 16 = 44 GiB, leaving
                    system services (jellyfin swaps ~2 GiB) the rest.
    oomd 50%      = the pressure backstop for the livelock case hard
                    caps can miss: sustained memory-pressure ≥50% on the
                    user slice kills the worst-offending cgroup before
                    system-wide thrash (upstream mkDefault is 80% — the
                    2026-07-09 event froze the desktop at ~22% system-wide
                    full-stall, so 80% would never fire in practice).

    If a legitimate workload trips these, the right response is fewer
    concurrent agent sessions (or more RAM), not a bigger cap — the freeze
    proved the marginal session is parked heap, not useful work.

    THIRD CALIBRATION — the 2026-07-20 fleet kill: caps + oomd WORKED
    (desktop survived, ~3 min recovery), but the whole Herdr fleet
    shared one ghostty transient scope, so the per-scope 60% trip
    (oomd.conf default; the 50% below governs only user@'s own cgroup)
    killed 908 processes in one shot — and the actual swap squatter
    (browser, separate scope) survived the victim selection. Per-pane
    scopes now bound a kill to one lane: home.nix
    programs.bash.initExtra + docs/reports/
    2026-07-20-oomd-agent-fleet-kill.md.
  */
  systemd.services."user@".serviceConfig = {
    MemoryHigh = "24G";
    MemoryMax = "28G";
    MemorySwapMax = "16G";
    ManagedOOMMemoryPressureLimit = "50%";
  };
  /*
    Same caps at the TRUE user boundary. user@ bounds only its own
    subtree — a Herdr fleet relaunched from a login shell lands in
    session-N.scope, a SIBLING of user@, and escapes every cap above
    (observed 2026-07-20 evening: 12+ GiB fleet, zero containment).
    user-1000.slice contains the session scopes AND user@, so the
    budget holds regardless of where the fleet is launched from.
    Single-user machine; the UID-specific name is fine.
  */
  systemd.slices."user-1000".sliceConfig = {
    MemoryHigh = "24G";
    MemoryMax = "28G";
    MemorySwapMax = "16G";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "50%";
  };
  systemd.oomd.enableUserSlices = true;

  /*
    Station-side Gatus probes for non-HTTP services. HTTP services
    behind Caddy are auto-probed via nori.lanRoutes.<n>.monitor.

    Mutual observability: station probes Pi's Blocky + SSH via tailnet
    IP; pi has matching probes for station (modules/machines/pi/default.nix).
    Each host's Gatus alerts via ntfy.sh directly (no local-ntfy
    dependency), so one host's outage gets caught by the other.
  */
  nori.gatusProbes = {
    blocky-dns.url = "tcp://127.0.0.1:53";
    samba-smb.url = "tcp://127.0.0.1:445";
    pi-blocky-dns.url = "tcp://${config.nori.hosts.pi.tailnetIp}:53";
    pi-ssh.url = "tcp://${config.nori.hosts.pi.tailnetIp}:22";
    aurora-ssh.url = "tcp://${config.nori.hosts.aurora.tailnetIp}:22";
    aurora-samba.url = "tcp://${config.nori.hosts.aurora.tailnetIp}:445";
  };
}
