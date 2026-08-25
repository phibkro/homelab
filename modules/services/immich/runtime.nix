{
  config,
  inputs,
  pkgs,
  ...
}:

let
  /*
    Build ONNX Runtime from the same globally CUDA-enabled package set used by
    the nixos-cuda Hydra jobset. Overriding only onnxruntime's argument changes
    its dependency graph and therefore misses the public binary cache.
  */
  cudaPkgs = import inputs.nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = config.nixpkgs.config // {
      cudaSupport = true;
    };
  };
in
{
  /*
    Immich — self-hosted photo management. Phone → server auto-upload,
    face recognition, object detection, shared albums.

    Storage split: managed library under _immich-managed/ on the
    family-vault photos subvolume; service state (DB, ML weights, dumps)
    stays on root NVMe. Existing user-organized photos sit alongside the
    managed library and remain available through Immich external libraries.

    First-run setup:
      1. Visit https://photos.home.phibkro.org
      2. Create admin account on first-connect form
      3. Settings → Users → Add User per family member
      4. On phone: install Immich app from app store, point at
         https://photos.home.phibkro.org over tailnet, log in, enable
         auto-backup
      5. (optional) Import existing photos through the web UI
         (Settings → External Library) or `immich-cli upload`
  */
  nixpkgs.overlays = [
    (_: _: {
      inherit (cudaPkgs) onnxruntime;
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
    # ML is co-located on the workstation. The upstream module wires the
    # server to the loopback ML endpoint, avoiding a network dependency.
    machine-learning.enable = true;

    # accelerationDevices still relevant for immich-server's NVENC
    # transcoding path (HW video conversion). Keep set.
    accelerationDevices = config.nori.gpu.nvidiaDevices;
  };

  # Joins `media` to read the user-organized photo tree if you point
  # External Library at it.
  users.users.immich.extraGroups = [ "media" ];

  systemd.tmpfiles.rules = [
    "d ${config.nori.fs.photos.path}/_immich-managed 0750 immich immich -"
  ];

  nori.harden.immich-server.binds = [ config.nori.fs.photos.path ];

  nori.backups.immich.skip = "Photos covered by media-irreplaceable (@photos); DB dumps via Pattern B at /var/lib/immich/backups also in media-irreplaceable.";
}
