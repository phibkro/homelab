{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "family-tier"
    "media-reader"
    "stateful"
  ];

  endpoints.audio = {
    port = 4533;
    publicStatus = true;
    exposeOnTailnet = true;
    reachability = "internet";
    monitor = { };
    audience = "family";
    noAuthReason = "Navidrome and OpenSubsonic clients use native per-user credentials; proxy-cookie or OIDC gates break most clients";
    dashboard = {
      title = "Navidrome";
      icon = "sh:navidrome";
      group = "Consume";
      description = "Subsonic-protocol music streaming";
    };
  };
}
