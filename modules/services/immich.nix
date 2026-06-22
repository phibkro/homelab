{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkMerge [
  {
    nori.services.immich.tags = [
      "family-tier"
      "media-reader"
      "stateful"
    ];

    /*
      Web-UI-managed OIDC (like Jellyseerr/Beszel). Immich stores its
      OAuth config in postgres (system_config table); env-var override
      support shifted in 1.100+ and isn't reliable for the OAuth
      subtree, so the operator pastes the raw secret + callback URI
      into the admin UI on first run.

      First-run setup:
        1. just generate-oidc-key photos
        2. sops secrets/secrets.yaml — paste the two values
        3. just rebuild
        4. https://photos.nori.lan → admin login (master account from
           initial Immich setup) → Administration → Settings → OAuth:
             Issuer URL:    https://auth.nori.lan
             Client ID:     photos
             Client Secret: cat /run/secrets/oidc-photos-client-secret
                             (sudo on workstation)
             Scope:         openid email profile
             Auto Register: on
             Auto Launch:   off
           Save. The redirect URI in Authelia (auto-set by lan-route via
           `oidc.redirectPath`) is https://photos.nori.lan/auth/login —
           that's what Immich's frontend handles.
    */
    nori.lanRoutes.photos = {
      port = 2283;
      runsOn = "aurora";
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
  }
  (lib.mkIf config.nori.services.immich.enabled {
    /*
      Immich — self-hosted photo management. Phone → server auto-upload,
      face recognition, object detection, shared albums.

      Storage split: managed library under _immich-managed/ on @photos
      (capacity-bound, IronWolf); service state (DB, ML weights, dumps)
      on root NVMe. Pre-existing user-organized photos at
      /mnt/media/photos/{2022, Canon EOS, ...} sit alongside
      _immich-managed/ — Immich won't see them unless explicitly imported
      via the web UI (External Library) or `immich-cli upload`.

      First-run setup:
        1. Visit https://photos.nori.lan
        2. Create admin account on first-connect form
        3. Settings → Users → Add User per family member
        4. On phone: install Immich app from app store, point at
           https://photos.nori.lan over tailnet, log in, enable
           auto-backup
        5. (optional) Import existing /mnt/media/photos/{2022,...}
           via the web UI (Settings → External Library) or
           `immich-cli upload`
    */
    /*
      CUDA ML inference (face detection, smart search). Overlay swaps
      onnxruntime to a cudaSupport=true build so the Python bindings
      pick up the CUDA execution provider at runtime. Only `cudaSupport`
      is overridden — defaults match cache.nixos-cuda.org's build, so
      the prebuilt artifact substitutes instead of triggering a local
      nvcc compile (~30 min on this CPU).
    */
    nixpkgs.overlays = [
      (_: prev: {
        onnxruntime = prev.onnxruntime.override { cudaSupport = true; };
      })
    ];

    services.immich = {
      enable = true;
      user = "immich";
      group = "immich";
      host = "0.0.0.0";
      port = 2283;
      mediaLocation = "${config.nori.fs.photos.path}/_immich-managed";

      database.enable = true; # dedicated postgres + VectorChord ext
      redis.enable = true;
      /*
        ML offloaded to aurora (modules/machines/aurora/default.nix) — the 5060
        Ti stays dedicated to ollama, no contention on heavy photo
        ingest. immich-server reaches the remote ML via env override
        below. Maxwell 950M on aurora is plenty for CLIP + face
        detection workloads.
      */
      machine-learning.enable = false;

      # accelerationDevices still relevant for immich-server's NVENC
      # transcoding path (HW video conversion). Keep set.
      accelerationDevices = config.nori.gpu.nvidiaDevices;
    };

    /*
      Point immich-server at aurora's ML over tailnet. mkForce because
      the upstream module sets this env at the same priority pointing
      at the local ML port; we override to the remote aurora endpoint.
    */
    systemd.services.immich-server.environment.IMMICH_MACHINE_LEARNING_URL =
      lib.mkForce "http://${config.nori.hosts.aurora.tailnetIp}:3003";

    /*
      ML-side knobs (tunings, harden entry, resource caps) DROPPED with
      the aurora migration. Workstation no longer runs the ML unit, so
      any override targeting immich-machine-learning here produces a
      unit with no ExecStart — systemd refuses to load it and activation
      fails. Aurora-side tuning lives in modules/machines/aurora/default.nix.
    */

    # Joins `media` to read the user-organized photo tree if you point
    # External Library at it.
    users.users.immich.extraGroups = [ "media" ];

    systemd.tmpfiles.rules = [
      "d ${config.nori.fs.photos.path}/_immich-managed 0750 immich immich -"
    ];

    nori.harden.immich-server.binds = [ config.nori.fs.photos.path ];

    nori.backups.immich.skip = "Photos covered by media-irreplaceable (@photos); DB dumps via Pattern B at /var/lib/immich/backups also in media-irreplaceable.";
  })
]
