let
  # Operator pause, 2026-07-31. Keep placement and retained state while
  # suppressing the runtime and every endpoint-derived projection.
  active = false;
in
{
  inherit active;
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ../runtime.nix;
  tags = [ "media-server" ];

  endpoints =
    if active then
      {
        downloads = {
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
    else
      { };
}
