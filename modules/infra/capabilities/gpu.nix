{ lib, ... }:

/**
  ## GPU access pattern

  Services that need the GPU set `accelerationDevices` (or systemd
  `DeviceAllow`) from `config.nori.gpu.nvidiaDevices` — single source
  of truth, declared per host in that host's `hardware.nix`.

  | Service | Status | Resource |
  |---|---|---|
  | Ollama (CUDA) | live | 14+ GiB VRAM at idle with model loaded |
  | Immich (CUDA ML + NVENC) | live | NVENC encode, ML inference (on aurora's GTX 950M) |
  | Jellyfin (NVENC) | OS-level live | Web-UI flag still off (ROADMAP item) |

  Driver split:

   - **workstation** (RTX 5060 Ti, Blackwell) — `hardware.nvidia.package =
     config.boot.kernelPackages.nvidiaPackages.production`. 595.58.03+
     on 26.05; Blackwell support landed.
   - **aurora** (GTX 950M, Maxwell) — `legacy_535` branch (Maxwell GPUs
     are out of the production branch's supported list).
   - **pavilion, pi** — no GPU; `nori.gpu.nvidiaDevices = [ ]` default.

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
