{ config, lib, pkgs, ... }:

# Workstation system + per-process metrics → scraped by pi VictoriaMetrics.
#
# Two exporters because they target different cardinality regimes:
#   * node-exporter  (:9100) — system aggregates: CPU, mem, fs, net, swap.
#                              Low cardinality, broad coverage.
#   * process-exporter (:9256) — per-process RSS / CPU / FD count, grouped
#                                by `comm`. Higher cardinality but bounded
#                                by N processes. THIS is the leak hunter.
#
# Bind on the tailnet IP only — these are operator-tier observability
# endpoints, not LAN-public. VM on pi scrapes them via the tailnet route.

let
  tailnetIp = config.nori.hosts.${config.networking.hostName}.tailnetIp;
in
{
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = tailnetIp;
    port = 9100;
    # Default collector set is fine; explicitly enable processes
    # (counts, states) which isn't on by default. RSS-per-process
    # lives in process-exporter below, NOT here.
    enabledCollectors = [ "processes" "systemd" ];
  };

  services.prometheus.exporters.process = {
    enable = true;
    listenAddress = tailnetIp;
    port = 9256;
    # Group by the command name (`comm`). One time-series per unique
    # binary, regardless of PID churn. The bounded {{.Comm}} keeps
    # cardinality predictable (~hundreds, not unbounded by PID).
    settings.process_names = [
      {
        name = "{{.Comm}}";
        cmdline = [ ".+" ];
      }
    ];
  };

  # The upstream NixOS module hardens process-exporter with an empty
  # CapabilityBoundingSet, which blocks it from reading other-UID
  # processes' /proc/<pid>/cmdline — and our config matches on cmdline.
  # Without the cap the exporter publishes only its own Go metrics and
  # zero `namedprocess_namegroup_*` series. Grant read-only ptrace.
  systemd.services.prometheus-process-exporter.serviceConfig = {
    CapabilityBoundingSet = [ "CAP_SYS_PTRACE" ];
    AmbientCapabilities = [ "CAP_SYS_PTRACE" ];
  };

  # Open the scrape ports to the tailnet only — pi reaches them via
  # the workstation tailnet IP. Default-deny everywhere else.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 9100 9256 ];
}
