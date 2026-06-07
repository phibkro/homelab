{ lib, ... }:

{
  # nori.gpu.nvidiaDevices — single source of truth for NVIDIA device
  # nodes. Services that need GPU access read this rather than hardcode
  # paths, so a GPU swap is a one-line change.
  #
  # Compute-only by design: nvidia-modeset (display) and
  # nvidia-uvm-tools (profiling) aren't in this set.
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
