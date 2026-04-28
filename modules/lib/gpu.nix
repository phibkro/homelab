{ lib, ... }:

{
  # nori.gpu.nvidiaDevices — single source of truth for NVIDIA device
  # nodes. Services that need GPU access set their accelerationDevices
  # (or equivalent systemd DeviceAllow) to this value rather than
  # hardcoding paths, so a GPU swap or additional card is a one-line
  # change here.
  #
  # Only compute-relevant nodes are listed. nvidia-modeset is a display
  # concern and not needed by server-side inference or transcoding.
  # nvidia-uvm-tools is a profiling aid, not required at runtime.
  #
  # Confirmed present on nori-station (RTX 5060 Ti / Blackwell):
  #   /dev/nvidia0        — GPU compute
  #   /dev/nvidiactl      — driver control node
  #   /dev/nvidia-uvm     — unified virtual memory (required for CUDA)
  options.nori.gpu.nvidiaDevices = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "/dev/nvidia0"
      "/dev/nvidiactl"
      "/dev/nvidia-uvm"
    ];
    description = ''
      NVIDIA device nodes exposed to services that opt in to GPU
      access. Consumed by services.immich.accelerationDevices and any
      future service whose NixOS module uses a DeviceAllow-style
      option. Override at the host level if the GPU inventory changes.
    '';
  };
}
