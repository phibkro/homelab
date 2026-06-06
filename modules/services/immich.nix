{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Immich — self-hosted photo management. Phone → server auto-upload,
  # face recognition, object detection, shared albums. The photo
  # equivalent of Jellyfin (which is video-focused). The Phase 5
  # service originally planned but deferred until after backup
  # infrastructure landed.
  #
  # Architecture: server + redis + postgres (with VectorChord for
  # vector search) + ML worker (uses NVIDIA GPU for face/object
  # detection inference). All four sub-services provisioned by the
  # NixOS module; we just enable + point at the right paths.
  #
  # Storage:
  #   /mnt/media/photos/_immich-managed   — uploads / library /
  #                                          profile (managed by
  #                                          Immich; capacity-bound,
  #                                          lives on @photos
  #                                          subvolume on IronWolf)
  #   /var/lib/immich                      — service state (DB, ML
  #                                          model weights, backup
  #                                          dumps) on root NVMe
  #
  # Pre-existing user-organized photos at /mnt/media/photos/{2022,
  # Canon EOS, ...} sit alongside _immich-managed/ — Immich won't
  # see them unless explicitly imported via the web UI or CLI.
  #
  # Backup: Pattern B per SERVICES.md § "Backup-correctness patterns". Immich writes Postgres
  # dumps to /var/lib/immich/backups on a schedule; restic picks up
  # that path + the photos themselves (already in
  # media-irreplaceable.include via /mnt/media/photos). The dumps path
  # is added to backup/restic.nix in this commit.
  #
  # First-run setup:
  #   1. Visit https://photos.nori.lan
  #   2. Create admin account on first-connect form
  #   3. Settings → Users → Add User per family member
  #   4. On phone: install Immich app from app store, point at
  #      https://photos.nori.lan over tailnet, log in, enable
  #      auto-backup
  #   5. (optional) Import existing /mnt/media/photos/{2022,...}
  #      via the web UI (Settings → External Library) or
  #      `immich-cli upload`
  # CUDA ML inference (face detection, smart search). Overlay swaps
  # onnxruntime to a cudaSupport=true build so the Python bindings
  # pick up the CUDA execution provider at runtime. Only `cudaSupport`
  # is overridden — defaults match cache.nixos-cuda.org's build, so
  # the prebuilt artifact substitutes instead of triggering a local
  # nvcc compile (~30 min on this CPU).
  nixpkgs.overlays = [
    (_: prev: {
      onnxruntime = prev.onnxruntime.override { cudaSupport = true; };
    })
  ];

  services.immich = {
    enable = true;
    user = "immich";
    group = "immich";
    host = "127.0.0.1";
    port = 2283;
    mediaLocation = "${config.nori.fs.photos.path}/_immich-managed";

    database.enable = true; # dedicated postgres + VectorChord ext
    redis.enable = true;
    # ML offloaded to aurora (machines/aurora/default.nix) — the 5060
    # Ti stays dedicated to ollama, no contention on heavy photo
    # ingest. immich-server reaches the remote ML via env override
    # below. Maxwell 950M on aurora is plenty for CLIP + face
    # detection workloads.
    machine-learning.enable = false;

    # accelerationDevices still relevant for immich-server's NVENC
    # transcoding path (HW video conversion). Keep set.
    accelerationDevices = config.nori.gpu.nvidiaDevices;
  };

  # Point immich-server at aurora's ML over tailnet. mkForce because
  # the upstream module sets this env at the same priority pointing
  # at the local ML port; we override to the remote aurora endpoint.
  systemd.services.immich-server.environment.IMMICH_MACHINE_LEARNING_URL =
    lib.mkForce "http://${config.nori.hosts.aurora.tailnetIp}:3003";

  # Workstation-side ML tunings DROPPED — ML now lives on aurora
  # (see machines/aurora/default.nix). The historical knobs were
  # workstation-specific (5060 Ti's 16 GB VRAM = 1 worker; 5600X's
  # 12 threads = 4 request threads; LD_LIBRARY_PATH for the local
  # onnxruntime CUDA build). Aurora has different hardware (Maxwell
  # GTX 950M, 2 GB VRAM, Skylake-H 4c/8t) and its own tuning lives
  # there. Keeping these here as a dead override produces a unit
  # file with no ExecStart on workstation — systemd refuses to load
  # it, the rebuild fails.

  # Cross-service photo access: Immich joins `media` so it can read
  # the existing user-organized photo tree if you point External
  # Library at it; future services (e.g. PhotoPrism) would do the same.
  users.users.immich.extraGroups = [ "media" ];

  # Bootstrap the immich-managed subdir at activation. The mediaLocation
  # path must exist and be writable by `immich` before the service
  # starts; tmpfiles creates it with the right ownership.
  systemd.tmpfiles.rules = [
    "d ${config.nori.fs.photos.path}/_immich-managed 0750 immich immich -"
  ];

  # Default-deny FS hardening for the server only. ML's hardening
  # lives on aurora now (when added there); workstation doesn't run
  # the ML unit, so the harden.immich-machine-learning entry that
  # was here is dropped — leaving it produced a malformed unit when
  # services.immich.machine-learning.enable = false (no ExecStart +
  # our overrides = systemd refuses to load).
  nori.harden.immich-server.binds = [ config.nori.fs.photos.path ];

  # Resource caps on ML — historical workstation tuning (CPUQuota
  # 600%, MemoryMax 16G) was sized for the 5600X + 5060 Ti shape.
  # Aurora has different hardware; if it needs caps, set them there.
  # Keeping these here while machine-learning.enable=false produced
  # a unit with no ExecStart and broke activation.

  # Web-UI-managed OIDC (like Jellyseerr/Beszel). Immich stores its
  # OAuth config in postgres (system_config table); env-var override
  # support shifted in 1.100+ and isn't reliable for the OAuth
  # subtree, so the operator pastes the raw secret + callback URI
  # into the admin UI on first run.
  #
  # First-run setup:
  #   1. just oidc-key photos
  #   2. sops secrets/secrets.yaml — paste the two values
  #   3. just rebuild
  #   4. https://photos.nori.lan → admin login (master account from
  #      initial Immich setup) → Administration → Settings → OAuth:
  #        Issuer URL:    https://auth.nori.lan
  #        Client ID:     photos
  #        Client Secret: cat /run/secrets/oidc-photos-client-secret
  #                        (sudo on workstation)
  #        Scope:         openid email profile
  #        Auto Register: on
  #        Auto Launch:   off
  #      Save. The redirect URI in Authelia (auto-set by lan-route via
  #      `oidc.redirectPath`) is https://photos.nori.lan/auth/login —
  #      that's what Immich's frontend handles.
  nori.lanRoutes.photos = {
    port = 2283;
    monitor = { };
    audience = "family";
    oidc = {
      clientName = "Immich";
      redirectPath = "/auth/login";
    };
    dashboard = {
      title = "Immich";
      icon = "si:immich";
      group = "Consume";
      description = "Photo library + face recognition";
    };
  };

  # Photos at /mnt/media/photos/_immich-managed live on the
  # @photos subvolume, already covered by media-irreplaceable.
  # Pattern B SQL dumps land at /var/lib/immich/backups (Immich's
  # web-UI Scheduled Database Backup, cron 02:00) — also in
  # media-irreplaceable. Everything else under /var/lib/immich is
  # ML models + transcoded thumbnails (re-derivable).
  nori.backups.immich.skip = "Photos covered by media-irreplaceable (@photos); DB dumps via Pattern B at /var/lib/immich/backups also in media-irreplaceable.";
}
