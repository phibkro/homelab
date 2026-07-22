{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
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
