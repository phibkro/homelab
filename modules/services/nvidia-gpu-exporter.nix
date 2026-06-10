{
  config,
  lib,
  pkgs,
  ...
}:

# NVIDIA GPU power + utilisation metrics → scraped by pi VictoriaMetrics.
#
# Wraps the upstream utkuozdemir/nvidia_gpu_exporter, which shells out
# to nvidia-smi and exposes the result on :9835. Power draw lives in
# `nvidia_smi_power_draw_watts` — the load-bearing series for the
# electricity-bill audit.
#
# Conditional on `config.nori.gpu.nvidiaDevices != [ ]` — same gate
# the immich + ollama services use, so only hosts that have NVIDIA
# devices run the exporter. pi + pavilion silently skip.

let
  tailnetIp = config.nori.hosts.${config.networking.hostName}.tailnetIp;
  hasNvidia = config.nori.gpu.nvidiaDevices != [ ];
in
{
  nori.backups.nvidia-gpu-exporter.skip = "Stateless scrape exporter; shells out to nvidia-smi, no on-disk state.";
  nori.harden.nvidia-gpu-exporter = lib.mkIf hasNvidia { };

  systemd.services.nvidia-gpu-exporter = lib.mkIf hasNvidia {
    description = "NVIDIA GPU metrics exporter (nvidia-smi → Prometheus)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      config.hardware.nvidia.package.bin # provides nvidia-smi
    ];
    serviceConfig = {
      ExecStart = "${pkgs.prometheus-nvidia-gpu-exporter}/bin/nvidia_gpu_exporter --web.listen-address=${tailnetIp}:9835";
      DynamicUser = true;
      Restart = "on-failure";
      # nvidia-smi reads /dev/nvidia* nodes — allow them. Same
      # device-allow shape as services consuming the GPU.
      DeviceAllow = map (d: "${d} rwm") config.nori.gpu.nvidiaDevices;
      PrivateDevices = false; # need /dev/nvidia*
    };
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.mkIf hasNvidia [ 9835 ];
}
