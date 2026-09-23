_:

{
  # Bound both resident memory and swap across all operator sessions. These
  # limits preserve the desktop during runaway agent workloads. Calibration:
  # docs/archive/reports/2026-07-20-oomd-agent-fleet-kill.md.
  systemd.services."user@".serviceConfig = {
    MemoryHigh = "75%";
    MemoryMax = "87.5%";
    MemorySwapMax = "16G";
    ManagedOOMMemoryPressureLimit = "50%";
  };
  systemd.slices."user-1000".sliceConfig = {
    MemoryHigh = "75%";
    MemoryMax = "87.5%";
    MemorySwapMax = "16G";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "50%";
  };
  systemd.oomd.enableUserSlices = true;

  # Builder demand must be contained at the allocator, independently of user
  # pressure. Keep swap bounded alongside RAM to avoid prolonged reclaim.
  # docs/archive/reports/2026-07-30-nix-build-memory-saturation.md.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryHigh = "4G";
    MemorySwapMax = "8G";
    MemoryMax = "12G";
  };
  nix.settings = {
    max-jobs = 4;
    cores = 3;
    # CI-built closures for the llm-agents.nix package pin.
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

}
