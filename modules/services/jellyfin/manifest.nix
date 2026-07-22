/*
  Global, secret-free Jellyfin catalog manifest.

  Safe to evaluate for every host and for deployment/documentation tooling.
  Host-local users, units, storage access, backup paths, and secrets belong in
  runtime.nix and never enter this projection.
*/
{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "media-server"
    "family-tier"
    "gpu-bound"
    "stateful"
  ];

  endpoints.media = {
    port = 8096;
    publicStatus = true;
    exposeOnTailnet = true;
    monitor = { };
    audience = "family";
    noAuthReason = "mobile/TV clients bypass cookie-based forward-auth; native SSO plugin has sharp historical edges";
    dashboard = {
      title = "Jellyfin";
      icon = "si:jellyfin";
      group = "Consume";
      description = "Movies, shows, music — server-rendered";
    };
  };
}
