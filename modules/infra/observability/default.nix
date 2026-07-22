_:

/**
  Observability concern — metrics, logs, monitoring, alerting.

  PaaS observability: collection (exporters), storage (TSDB + logs
  index), query (Grafana), monitoring (Gatus), alerting (ntfy +
  heartbeat). Workload runtimes select exporters and daemons; the explicit
  `log-forwarder` system profile selects Vector on each participating host.
  Daemon-side services
  (VictoriaMetrics, VictoriaLogs, Gatus, Beszel hub, ntfy server,
  Grafana) activate only where opted in.

  Files in this folder split between FRAMEWORK (per-route monitor
  schema fragment) and SERVICES (daemons + clients):

   - `gatus.nix`               status-page monitor daemon
                               (consumes per-route monitors
                               declared via
                               `modules/infra/networking/default.nix`)
   - `victoriametrics/`        metrics TSDB
   - `victorialogs/`           logs index (server + bundle)
   - `grafana.nix`             dashboards UI
   - `grafana-dashboards/`     dashboard sources
   - `beszel/`                 high-level metrics (hub + agent
                               split-module)
   - `ntfy/`                   alert channel (server + per-host
                               notify@ client)
   - `node-exporter/`          Linux metrics exporter
   - `nvidia-gpu-exporter/`    GPU metrics
   - `vector.nix`              journald → VictoriaLogs shipper
                               (was modules/infra/observability/vector.nix)
   - `heartbeat.nix`           dead-man-switch ping →
                               healthchecks.io
   - `disk-alert.nix`          per-fs disk-space alert
*/
{
  imports = [ ./alerts.nix ];
}
