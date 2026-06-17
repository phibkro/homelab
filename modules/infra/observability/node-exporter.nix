{
  config,
  lib,
  pkgs,
  ...
}:

/**
  Workstation system + per-process metrics → scraped by pi VictoriaMetrics.

  Two exporters because they target different cardinality regimes:
    * node-exporter  (:9100) — system aggregates: CPU, mem, fs, net, swap.
                               Low cardinality, broad coverage.
    * process-exporter (:9256) — per-process RSS / CPU / FD count, grouped
                                 by `comm`. Higher cardinality but bounded
                                 by N processes. THIS is the leak hunter.

  Bind on the tailnet IP only — these are operator-tier observability
  endpoints, not LAN-public. VM on pi scrapes them via the tailnet route.
*/

let
  tailnetIp = config.nori.hosts.${config.networking.hostName}.tailnetIp;
in
lib.mkMerge [
  { nori.services.node-exporter.tags = [ "observability" ]; }
  (lib.mkIf config.nori.services.node-exporter.enabled {
    nori.backups.node-exporter.skip = "Stateless scrape exporters (node + process); no on-disk state.";
    nori.harden.prometheus-node-exporter = { };
    nori.harden.prometheus-process-exporter = { };

    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = tailnetIp;
      port = 9100;
      /*
        Default collector set is fine; explicitly enable processes
        (counts, states) which isn't on by default. RSS-per-process
        lives in process-exporter below, NOT here.
      */
      enabledCollectors = [
        "processes"
        "systemd"
        /*
          RAPL — CPU + DRAM energy counters via /sys/class/powercap/
          intel-rapl/. Despite the name, registers AMD energy counters
          too (Zen+; verified on workstation 2026-06-07). pavilion's
          Phenom II era CPU has no RAPL; collector reports no metrics
          there, no harm. Power = rate(node_rapl_*_joules_total[5m]).
        */
        "rapl"
      ];
    };

    /*
      The RAPL sysfs entries are mode 0400 root:root on modern kernels
      (CVE-2020-8694 / Platypus side-channel mitigation). node-exporter
      runs as DynamicUser and can't read them by default → collector
      produces zero metrics. CAP_DAC_READ_SEARCH lets the exporter
      bypass the read-permission check without granting full root.
    */
    systemd.services.prometheus-node-exporter.serviceConfig = {
      CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
      AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
    };

    /*
      Bind happens on the tailnet IP; the upstream unit's
      `After=network.target` reaches active before tailscaled has
      brought up tailscale0, so the first start attempt at boot fails
      to bind and exits 1. Systemd's Restart=on-failure retries 1s
      later and that succeeds — but the failure triggers OnFailure →
      notify@ which then sits in its 2-min recovery-window sleep
      (~120s of background "boot blame" per systemd-analyze).
      Declaring the actual dependency stops the spurious alert chain.
      Same shape for process-exporter (also tailnet-bound).
    */
    systemd.services.prometheus-node-exporter.after = [ "tailscaled.service" ];
    systemd.services.prometheus-process-exporter.after = [ "tailscaled.service" ];

    services.prometheus.exporters.process = {
      enable = true;
      listenAddress = tailnetIp;
      port = 9256;
      /*
        Group by the command name (`comm`). One time-series per unique
        binary, regardless of PID churn. The bounded {{.Comm}} keeps
        cardinality predictable (~hundreds, not unbounded by PID).
      */
      settings.process_names = [
        {
          name = "{{.Comm}}";
          cmdline = [ ".+" ];
        }
      ];
    };

    /*
      The upstream NixOS module hardens process-exporter with an empty
      CapabilityBoundingSet, which blocks it from reading other-UID
      processes' /proc/<pid>/cmdline — and our config matches on cmdline.
      Without the cap the exporter publishes only its own Go metrics and
      zero `namedprocess_namegroup_*` series. Grant read-only ptrace.
    */
    systemd.services.prometheus-process-exporter.serviceConfig = {
      CapabilityBoundingSet = [ "CAP_SYS_PTRACE" ];
      AmbientCapabilities = [ "CAP_SYS_PTRACE" ];
    };

    # Tailnet-only scrape ports — pi reaches them via the host's tailnet IP.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      9100
      9256
    ];
  })
]
