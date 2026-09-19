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
  runtimeModule = ./nixos.nix;
  tags = [
    "family-tier"
    "stateful"
  ];

  endpoints.sync = {
    port = 8384;
    exposeOnTailnet = true;
    monitor = { };
    audience = "operator";
    dashboard = {
      title = "Syncthing";
      icon = "si:syncthing";
      group = "Personal";
      description = "Cross-device file sync";
      allowInsecure = true;
    };
  };
}
