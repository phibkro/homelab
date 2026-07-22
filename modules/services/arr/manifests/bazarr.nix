{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ../runtime.nix;
  tags = [ "media-server" ];

  endpoints.subtitles = {
    port = 6767;
    exposeOnTailnet = true;
    monitor = { };
    audience = "operator";
    dashboard = {
      title = "Bazarr";
      icon = "sh:bazarr";
      group = "Acquire";
      description = "Subtitle automation";
    };
  };
}
