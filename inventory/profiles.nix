/*
  Explicit reusable compositions.

  A profile changes only through review of this file; workload tags never add
  themselves to a host. `systemModules` is compiler-private and intentionally
  unused during Phase 1 while existing host imports remain authoritative.
*/
{
  base = {
    description = "Universal NixOS floor";
    systemModules = [ ../modules/machines/base ];
    workloads = [ ];
  };

  desktop = {
    description = "Operator-attached graphical workstation";
    systemModules = [ ../modules/machines/desktop ];
    workloads = [ ];
  };

  media-compute = {
    description = "GPU media serving, acquisition, and operator AI";
    systemModules = [ ];
    workloads = [
      "bazarr"
      "jellyfin"
      "jellyseerr"
      "lidarr"
      "ollama"
      "open-webui"
      "prowlarr"
      "qbittorrent"
      "radarr"
      "recyclarr"
      "samba"
      "sonarr"
      "stremio"
      "syncthing"
    ];
  };

  family-vault = {
    description = "Always-on family data and application tier";
    systemModules = [ ];
    workloads = [
      "btrbk-replication"
      "calibre-web"
      "filmder"
      "glance"
      "grafana"
      "heim"
      "immich"
      "komga"
      "miniflux"
      "navidrome"
      "paperless"
      "radicale"
      "restic-target"
      "samba"
      "suwayomi"
      "syncthing"
      "vaultwarden"
    ];
  };

  entry-plane = {
    description = "Always-on HTTP, DNS, identity, alert, and metrics hub";
    systemModules = [ ];
    workloads = [
      "authelia"
      "beszel-hub"
      "blocky"
      "caddy"
      "gatus"
      "heartbeat"
      "ntfy-server"
      "victorialogs-server"
      "victoriametrics"
    ];
  };

  observability-agent = {
    description = "Per-host metrics exporters and high-level agent";
    systemModules = [ ];
    workloads = [
      "beszel-agent"
      "node-exporter"
    ];
  };

  agent-host = {
    description = "Quarantined, disposable agent execution host";
    systemModules = [ ];
    workloads = [ ];
  };
}
