{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "family-tier"
    "stateful"
  ];

  endpoints.calendar = {
    port = 5232;
    exposeOnTailnet = true;
    monitor.path = "/.web/";
    audience = "family";
    noAuthReason = "CalDAV/CardDAV clients can't follow forward-auth redirects (htpasswd-only)";
    dashboard = {
      title = "Radicale";
      icon = "sh:radicale";
      group = "Personal";
      description = "CalDAV / CardDAV — phone calendar + contacts";
    };
  };
}
