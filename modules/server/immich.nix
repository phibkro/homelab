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
  # Backup: Pattern B per DESIGN.md L283-289. Immich writes Postgres
  # dumps to /var/lib/immich/backups on a schedule; restic picks up
  # that path + the photos themselves (already in
  # media-irreplaceable.paths via /mnt/media/photos). The dumps path
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
    mediaLocation = "/mnt/media/photos/_immich-managed";

    database.enable = true; # dedicated postgres + VectorChord ext
    redis.enable = true;
    machine-learning.enable = true; # face/object detection on RTX 5060 Ti

    # Grant immich-server (NVENC transcoding) and immich-machine-learning
    # (CUDA inference) access to the GPU. The NixOS module sets
    # PrivateDevices=true by default when this list is empty; setting it
    # to the canonical device list unlocks DeviceAllow for both units.
    accelerationDevices = config.nori.gpu.nvidiaDevices;
  };

  # CUDA execution provider .so is dlopen'd at runtime from
  # onnxruntime's capi/ dir under the python site-packages tree; the
  # second path covers the C++ shared library (libonnxruntime.so).
  # Without LD_LIBRARY_PATH the worker logs "Failed to find onnxruntime
  # CUDAExecutionProvider" and silently falls back to CPU.
  services.immich.machine-learning.environment.LD_LIBRARY_PATH =
    "${pkgs.python3Packages.onnxruntime}/lib:"
    + "${pkgs.python3Packages.onnxruntime}/${pkgs.python3.sitePackages}/onnxruntime/capi";

  # Cross-service photo access: Immich joins `media` so it can read
  # the existing user-organized photo tree if you point External
  # Library at it; future services (e.g. PhotoPrism) would do the same.
  users.users.immich.extraGroups = [ "media" ];

  # Bootstrap the immich-managed subdir at activation. The mediaLocation
  # path must exist and be writable by `immich` before the service
  # starts; tmpfiles creates it with the right ownership.
  systemd.tmpfiles.rules = [
    "d /mnt/media/photos/_immich-managed 0750 immich immich -"
  ];

  # Default-deny FS hardening for the server + ML worker. Both need
  # /mnt/media/photos for the managed subdir; ML also reads /var/lib
  # for model weights (covered by the NixOS module's StateDirectory).
  systemd.services.immich-server.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
    BindPaths = [ "/mnt/media/photos" ];
  };
  systemd.services.immich-machine-learning.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
    BindPaths = [ "/mnt/media/photos" ];

    # Resource caps. April 2026 incident: ML pipeline starved the
    # host for 4+ minutes (rtkit canary thread reported starvation
    # repeatedly; immich-machine-learning went unhealthy; desktop
    # hung; forced power-cycle). The kernel logged no thermal trip —
    # this was userspace CPU starvation, not heat. Cap so a runaway
    # ML workload can't take the rest of the system down with it.
    #
    # CPUQuota=600% on a 12-thread CPU = 6 cores' worth, leaving 6
    # for everything else (Caddy, Authelia, *arr, sshd, Hyprland).
    # MemoryMax=16G is half of system RAM; OOM-kill the cgroup
    # before the host enters thrash territory. MemoryHigh=12G is
    # the soft pressure point where reclaim begins.
    CPUQuota = "600%";
    MemoryHigh = "12G";
    MemoryMax = "16G";
    TasksMax = 4096;
  };

  nori.lanRoutes.photos = {
    port = 2283;
    monitor = { };
  };

  # Photos at /mnt/media/photos/_immich-managed live on the
  # @photos subvolume, already covered by media-irreplaceable.
  # Pattern B SQL dumps land at /var/lib/immich/backups (Immich's
  # web-UI Scheduled Database Backup, cron 02:00) — also in
  # media-irreplaceable. Everything else under /var/lib/immich is
  # ML models + transcoded thumbnails (re-derivable).
  nori.backups.immich.skip = "Photos covered by media-irreplaceable (@photos); DB dumps via Pattern B at /var/lib/immich/backups also in media-irreplaceable.";
}
