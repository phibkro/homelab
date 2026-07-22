{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "family-tier"
    "stateful"
  ];

  endpoints.sync = {
    port = 8384;
    runsOn = "workstation";
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
