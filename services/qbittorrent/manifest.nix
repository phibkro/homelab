let
  # Enabled for the local-first acquisition path. Sonarr and Radarr already
  # target the retained qBittorrent state; completed imports stay on @downloads.
  active = true;
in
{
  inherit active;
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ../../profiles/media-acquisition/nixos.nix;
  tags = [ "media-server" ];

  endpoints =
    if active then
      {
        downloads = {
          port = 8083;
          exposeOnTailnet = true;
          forwardAuth = { };
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
    else
      { };
}
