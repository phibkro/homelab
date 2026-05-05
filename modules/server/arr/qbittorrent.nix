{
  config,
  lib,
  pkgs,
  ...
}:

{
  # qBittorrent — torrent download client for the *arr stack. WebUI only
  # (no desktop GUI per the homelab's server/client separation).
  #
  # Default WebUI port is 8080 which collides with Open WebUI; remapped
  # to 8083. Torrent listen port (29170) is the default; firewall stays
  # default-deny — incoming peer connections are not currently accepted
  # (would need an inbound port forward on the residential router AND
  # an explicit firewall rule). Outgoing peer connections still work.
  #
  # First-run setup (one-shot, after rebuild):
  #   1. Visit https://downloads.nori.lan
  #   2. Login with default creds (printed in journalctl on first start;
  #      check `journalctl -u qbittorrent -g "WebUI password"`)
  #   3. Tools → Options:
  #        Downloads → Default save path:
  #          /mnt/media/streaming/.downloads/complete
  #        Downloads → Keep incomplete torrents in:
  #          /mnt/media/streaming/.downloads/incomplete
  #        Web UI → Authentication: change default password
  #        Connection → Listening port: 29170 (or whatever the module sets)
  #   4. Generate an API key under Web UI → Authentication for use by
  #      Sonarr/Radarr to drive downloads programmatically.
  services.qbittorrent = {
    enable = true;
    webuiPort = 8083;
    user = "qbittorrent";
    group = "qbittorrent";
    openFirewall = false;
  };

  # Group membership — `media` is the cross-service shared group on the
  # streaming subvolume. Every *arr + the download client are members so
  # hardlinks across .downloads/complete → movies/shows just work.
  users.users.qbittorrent.extraGroups = [ "media" ];

  # qBittorrent needs the @streaming subvolume for incomplete + complete
  # download staging; /var/lib/qbittorrent for state (auto-created by
  # the service, covered by the StateDirectory upstream).
  nori.harden.qbittorrent.binds = [ config.nori.fs.streaming.path ];

  # Exposed at https://downloads.nori.lan via Caddy. Auto-monitored at /
  # (qBittorrent's WebUI returns 401 without auth which Gatus reads as
  # service-up; that's fine — we just want to know the process answers).
  nori.lanRoutes.downloads = {
    port = 8083;
    monitor = { };
    # Forward-auth via Authelia. /api/* exempt so the *arr clients
    # (Sonarr, Radarr, Lidarr) can drive downloads via qBittorrent's
    # Web API using the per-app credentials configured on first run.
    forwardAuth.exemptPaths = [ "/api/*" ];
    dashboard = {
      title = "qBittorrent";
      icon = "si:qbittorrent";
      group = "Acquire";
      description = "Download client";
    };
  };

  # Pattern A — torrent state, resume data, *arr-tied categories.
  # Static `qbittorrent` user; real path with capital Q.
  nori.backups.qbittorrent.paths = [ "/var/lib/qBittorrent" ];
}
