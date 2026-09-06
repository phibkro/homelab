{ lib, ... }:

/**
  ## GPU access pattern

  Services that need the GPU set `accelerationDevices` (or systemd
  `DeviceAllow`) from `config.nori.gpu.nvidiaDevices` — single source
  of truth, declared per host in that host's `hardware.nix`.

  Workstation is the NVIDIA host (RTX 5060 Ti, Blackwell). Its hardware
  module selects `config.boot.kernelPackages.nvidiaPackages.production`;
  the locked package set determines the driver version. Ollama, Immich,
  and Jellyfin declare their local GPU requirements in their runtimes.
  These declarations do not establish live application acceleration or
  measured VRAM usage. Pi's production runtime is owned by Ansible.

  Fallback ladder if production breaks: `production` → `beta` →
  `latest` → explicit `mkDriver` pin.

  ## Why the registry shape

  Same Reader+Writer shape as `nori.lanRoutes` and `nori.harden`. Each
  host's `hardware.nix` is the Reader (sets `nori.gpu.nvidiaDevices`);
  each service that needs the GPU is the Writer (reads
  `config.nori.gpu.nvidiaDevices` for its `accelerationDevices` /
  `DeviceAllow` setting). GPU swap = edit one host's hardware.nix;
  every consuming service follows.

  Compute-only by design: `nvidia-modeset` (display) and
  `nvidia-uvm-tools` (profiling) aren't in the registry. Add them if
  a future workload needs display access or profiling.
*/

{
  /**
    `nori.gpu.nvidiaDevices` — single source of truth for NVIDIA
    device nodes. Services that need GPU access read this rather
    than hardcode paths, so a GPU swap is a one-line change.

    Compute-only by design: `nvidia-modeset` (display) and
    `nvidia-uvm-tools` (profiling) aren't in this set.
  */
  options.nori.gpu.nvidiaDevices = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      NVIDIA device nodes exposed to GPU-opted-in services
      (services.immich.accelerationDevices, future DeviceAllow-style
      consumers). Empty default lets GPU-less hosts pass through cleanly;
      GPU hosts set this in their hardware.nix.
    '';
    example = lib.literalExpression ''
      [
        "/dev/nvidia0"      # GPU compute
        "/dev/nvidiactl"    # driver control node
        "/dev/nvidia-uvm"   # unified virtual memory (required for CUDA)
      ]
    '';
  };
}
