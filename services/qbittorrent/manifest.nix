{
  # Enabled for the local-first acquisition path. Sonarr and Radarr already
  # target the retained qBittorrent state; completed imports stay on @downloads.
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "primary-service-host" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ../../profiles/media-acquisition/nixos.nix;
  tags = [ "media-server" ];

  endpoints.downloads = {
    port = 8083;
    exposeOnTailnet = true;
    forwardAuth.exemptPaths = [ ];
    monitor = { };
    audience = "operator";
    dashboard = {
      title = "qBittorrent";
      icon = "si:qbittorrent";
      group = "Acquire";
      description = "Download client";
    };
  };
}
