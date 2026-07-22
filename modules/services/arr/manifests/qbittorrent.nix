{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ../runtime.nix;
  tags = [ "media-server" ];

  endpoints.downloads = {
    port = 8083;
    exposeOnTailnet = true;
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
