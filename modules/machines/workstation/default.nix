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
    ./disko-family.nix
  ];

  # networking.hostName injected from the registry key in flake.nix.
  networking.useDHCP = lib.mkDefault true;

  /*
    Add the operator user to the `media` group so shell access and
    services running as `nori` can write to the media and family-library
    trees, which are owned root:media 02775 by the shared media setup.
    The group itself and this membership are declared elsewhere in the
    workstation profile; keep this host-specific prerequisite focused on
    the tmpfiles paths below.
  */
  users.users.nori.extraGroups = [ "media" ];

  /*
    Exa web-search credential for interactive OMP processes. SOPS decrypts the
    raw value for nori; the Home Manager OMP wrapper reads it only at launch
    and exports EXA_API_KEY to OMP without copying it into generated config.
  */
  sops.secrets.exa-api-key = {
    owner = "nori";
    mode = "0400";
  };

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

  /*
    2026-07-23: agents channel moved off ntfy.sh onto the self-hosted pi
    hub. FLEET/AGENT volume (every turn-end/permission/question ping from
    however many agents are running) was tripping ntfy.sh's public rate
    limit (429s, reproduced with a bare nori-alert call) — and it shares
    that quota with every OTHER alert on ntfy.sh, so a noisy fleet could
    silently starve a real infra alert of delivery.

    CRITICAL INFRA alerts (nori.alerts.channels.infra, wired in
    ntfy/notify.nix) deliberately STAY on ntfy.sh: they need to survive
    the homelab itself being down, so pointing them at a service the
    homelab hosts would be self-defeating. Fleet/agent alerts carry no
    such requirement — if pi is down, the phone will also see pi's other
    outage alerts (still on ntfy.sh) and losing agent chatter is a nonissue.

    The pi hub denies anonymous publish (auth-default-access = deny, see
    ntfy/server.nix + docs/runbooks/ntfy-auth-bootstrap.md) — reuse the
    same shared publisher token already provisioned there. It's read by
    home-manager's agent-notify, which runs as nori: same owner/mode as
    the topic secret above.
  */
  sops.secrets.ntfy-publisher-token = {
    owner = "nori";
    group = "keys";
    mode = "0440";
  };

  # The agents channel + route: agent-notify emits `--audience agents`,
  # this maps it to the dedicated topic. Defined here (not in the shared
  # home module) because the secret + nori-alert live at the system layer
  # on the host that runs the fleet.
  nori.alerts.channels.agents = {
    topicSecret = config.sops.secrets.ntfy-agents-channel.path;
    baseUrl = "https://alert.${config.nori.domain}";
    authTokenSecret = config.sops.secrets.ntfy-publisher-token.path;
  };
  nori.alerts.routes.agents = [ "agents" ];

  /*
    Fix-agent: ARMED on backup verification + snapshot + the backup jobs
    themselves. A real failure (surviving the recovery window)
    OnFailure-dispatches a boxed agent that diagnoses, fixes on an origin/main
    clone, validates with `nix flake check`, and opens a PR — PR-only, never
    deploys. Dry-run validated 2026-07-18 (it found + fixed the SFTP
    restic-check bug that PR carried).
    Design: docs/specs/2026-07-18-agent-fix-on-failure-design.md.

    The `restic-backups-*` half is DERIVED from services.restic.backups rather
    than hand-listed. 22 units is too many to keep in sync by hand, and the
    failure mode of a stale hand-list is silent: a new service's backup job
    would fail unwatched. Auditing this on 2026-07-26 found exactly that gap —
    restic-check-* was armed while every restic-backups-* unit was not, and
    five of them had failed since arming (user-data, qbittorrent, radarr,
    prowlarr) with only a notify@ ping. Deriving makes that drift
    unrepresentable: a new backup arrives armed.
  */
  nori.agentFix.enable = true;
  nori.agentFix.units = [
    "restic-check-weekly"
    "restic-check-monthly"
    "btrbk-root"
    "btrbk-family"
  ]
  ++ lib.optional (config.services.btrbk.instances ? media) "btrbk-media"
  ++ map (name: "restic-backups-${name}") (lib.attrNames config.services.restic.backups);

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

  # Pre-create the shared family-library and FLAC staging trees. The
  # family-library paths moved here with the Toshiba family vault; root:media
  # 02775 lets calibre-web, Komga, suwayomi, and Syncthing create content.
  systemd.tmpfiles.rules = [
    "d /mnt/family/library            02775 root media - -"
    "d /mnt/family/library/books      02775 root media - -"
    "d /mnt/family/library/comics     02775 root media - -"
    "d /mnt/family/library/manga      02775 root media - -"
    "d /mnt/family/library/music      02775 root media - -"
    "d /mnt/family/library/papers     02775 root media - -"
    "d /mnt/media/staging             0755  root root  - -"
    "d /mnt/media/staging/music-flac  2775  root media - -"
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
    FOURTH CALIBRATION — the 2026-07-30 build-driven fleet kill
    (docs/reports/2026-07-30-nix-build-memory-saturation.md).

    Every calibration above bounds the USER side. This one originated on
    the SYSTEM side, and none of them could see it: an agent ran
    `nix build .#aeneas .#charon`; `max-jobs` was unset so it resolved to
    `auto` = 12 concurrent derivations, and one of them
    (ocamlPackages.saturn's checkPhase) runs dscheck — an exhaustive
    interleaving model checker whose state space grows without bound. That
    single builder reached 1.77 GiB RSS + 3.0 GiB swap in 13 minutes and
    was still climbing.

    WHY NO USER-SIDE KNOB COULD HAVE HELPED: PSI is charged where the
    STALL happens, not where the allocation happened. The build took
    shared RAM without stalling itself, so system.slice sat at 0.32%
    full-pressure while user-1000.slice hit 23% — and oomd, which only
    monitors user slices here, culled six agent panes / 211 processes.
    The box recovered only because kill #6 happened to destroy the pane
    that OWNED the nix client, aborting the build as a side effect of
    destroying the victim. Pressure-based victim selection structurally
    cannot target a cgroup that steals memory without stalling itself.

    Hence a CEILING on the build, not another pressure trigger: a trigger
    fires on the stall (wrong side), a ceiling fires on the allocation
    (where the fault actually is).

    MemoryHigh     = throttle FIRST. Past 4 GiB the kernel reclaims
                     nix-daemon's OWN pages rather than the fleet's, so a
                     legitimately hungry derivation gets slow instead of
                     dying, and the cost lands on the build rather than on
                     innocent agents. This is the load-bearing setting.
    MemorySwapMax  = bounds the swap axis so throttling cannot turn into
                     unbounded disk thrash (the 01:03-01:09 failure mode).
    MemoryMax      = last-resort backstop, deliberately ABOVE any
                     legitimate derivation here. MEASURED CAVEAT: in
                     practice it is nearly unreachable, because MemoryHigh
                     throttling slows allocation faster than the builder
                     can climb — a 7 GiB allocation against a temporarily
                     lowered 5 GiB max with swap disabled never tripped it
                     in 300 s (memory.events max=0, oom_kill=0, high=55647).
                     So treat MemoryMax as insurance, not as the mechanism;
                     MemoryHigh is what actually contains a runaway. If it
                     ever does trip, nix-daemon is ~20 MiB against a
                     multi-GiB builder so oom_score selects the builder,
                     and upstream OOMPolicy=continue keeps the daemon up
                     (verified: daemon PID unchanged across the test).
    max-jobs/cores = bound aggregate demand so the ceiling is rarely
                     reached at all: 4 x 3 = 12 threads on 12 cores,
                     replacing auto(12) x all(12).

    ESCAPE HATCH for a known-huge derivation (chromium, kernel): build it
    with `--max-jobs 1` and raise MemoryHigh here temporarily. Do NOT raise
    MemoryHigh casually to make a build faster — that re-points the reclaim
    cost at the fleet, which is the whole defect being fixed.

    KNOWN TRADE-OFF, measured: because MemoryHigh throttles rather than
    fails, a genuine runaway no longer takes the box down — it crawls,
    pinned at 4 GiB resident + 8 GiB swap, indefinitely. Contained, but
    silent: `max-silent-time`/`timeout` are both 0 (infinite) here, so
    nothing ever surfaces it. Picking a threshold needs to know this
    host's longest legitimately-silent build, so it is left as follow-up
    #7 in the incident report rather than guessed at.

    NOT solvable via `nix.settings.use-cgroups`: nix 2.34 has the flag,
    but it isolates builds for accounting/cleanup and exposes no per-build
    memory limit. NOT solvable at system.slice level either — that slice
    legitimately carries ~15 GiB of media services (qbittorrent, jellyfin).
  */
  systemd.services.nix-daemon.serviceConfig = {
    MemoryHigh = "4G";
    MemorySwapMax = "8G";
    MemoryMax = "12G";
  };
  nix.settings = {
    max-jobs = 4;
    cores = 3;
  };

  /*
    Local non-HTTP service probe. Entry-plane DNS and SSH probes live in
    modules/profiles/entry-plane.nix; HTTP services derive probes from routes.
  */
  nori.gatusProbes.samba-smb.url = "tcp://127.0.0.1:445";
}
