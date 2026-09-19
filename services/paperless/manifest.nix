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
    "media-reader"
    "stateful"
  ];

  endpoints.papers = {
    port = 28981;
    exposeOnTailnet = true;
    monitor = { };
    dashboard = {
      title = "Paperless";
      icon = "si:paperlessngx";
      group = "Consume";
      description = "Document archive — OCR + full-text search";
    };
  };
}
