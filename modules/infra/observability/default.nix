_:

/**
  Observability concern — metrics, logs, monitoring, alerting.

  PaaS observability: collection (exporters), storage (TSDB + logs
  index), query (Grafana), monitoring (Gatus), alerting (ntfy +
  heartbeat). Universal exporters (node, nvidia-gpu, vector) ship
  on every host that imports this; daemon-side services
  (VictoriaMetrics, VictoriaLogs, Gatus, Beszel hub, ntfy server,
  Grafana) activate only where opted in.

  Files in this folder split between FRAMEWORK (per-route monitor
  schema fragment) and SERVICES (daemons + clients):

   - `gatus.nix`               status-page monitor daemon
                               (consumes per-route monitors
                               declared via
                               `modules/infra/networking/default.nix`)
   - `victoriametrics.nix`     metrics TSDB
   - `victorialogs/`           logs index (server + bundle)
   - `grafana.nix`             dashboards UI
   - `grafana-dashboards/`     dashboard sources
   - `beszel/`                 high-level metrics (hub + agent
                               split-module)
   - `ntfy/`                   alert channel (server + per-host
                               notify@ client)
   - `node-exporter.nix`       Linux metrics exporter
   - `nvidia-gpu-exporter.nix` GPU metrics
   - `vector.nix`              journald → VictoriaLogs shipper
                               (was modules/infra/observability/vector.nix)
   - `heartbeat.nix`           dead-man-switch ping →
                               healthchecks.io
   - `disk-alert.nix`          per-fs disk-space alert
*/
{
  imports = [
    ./gatus.nix
    ./victoriametrics.nix
    ./victorialogs/default.nix
    ./grafana.nix
    ./beszel/agent.nix
    ./ntfy/notify.nix
    ./node-exporter.nix
    ./nvidia-gpu-exporter.nix
    ./vector.nix
    ./heartbeat.nix
    ./disk-alert.nix
  ];
}
