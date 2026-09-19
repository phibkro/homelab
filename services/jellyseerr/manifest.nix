{
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
  tags = [
    "media-server"
    "family-tier"
  ];

  endpoints.requests = {
    port = 5055;
    publicStatus = true;
    exposeOnTailnet = true;
    reachability = "internet";
    monitor = { };
    audience = "family";
    noAuthReason = "Seerr authenticates family members with their existing Jellyfin accounts; generic OIDC is not supported upstream";
    dashboard = {
      title = "Seerr";
      icon = "sh:seerr";
      group = "Acquire";
      description = "Request shows / movies (family-facing)";
    };
  };
}
