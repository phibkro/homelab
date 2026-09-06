/*
  Explicit reusable compositions.

  A profile changes only through review of this file; workload tags never add
  themselves to a host. `systemModules` is compiler-private and selected
  before NixOS evaluation.
*/
{
  base = {
    description = "Common host baseline, realized by its deployment backend";
    systemModules = [ ../infra/common/nixos/default.nix ];
    workloads = [ ];
  };

  desktop = {
    description = "Operator-attached graphical workstation";
    systemModules = [ ../profiles/desktop/nixos/default.nix ];
    workloads = [ ];
  };

  log-forwarder = {
    description = "Per-host journald shipping to the central log index";
    systemModules = [ ../services/vector/nixos.nix ];
    workloads = [ ];
  };

  backup-source = {
    description = "Local rollback snapshots and explicitly enabled independent backup policy";
    systemModules = [
      ../services/btrbk/nixos.nix
      ../services/restic-backup/nixos.nix
      ../services/restore-drill/nixos.nix
    ];
    workloads = [ ];
  };

  research = {
    description = "Operator research acquisition tools colocated with their data sink";
    systemModules = [ ../profiles/research/nixos.nix ];
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
      "samba"
      "suwayomi"
      "syncthing"
      "vaultwarden"
    ];
  };

  entry-plane = {
    description = "Always-on HTTP, DNS, identity, alert, and metrics hub";
    # Production realization is exclusively Ansible-owned under infra/pi/.
    systemModules = [ ];
    workloads = [
      "authelia"
      "beszel-hub"
      "pihole"
      "caddy"
      "cloudflare-ddns"
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

}
