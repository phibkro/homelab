{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
  ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "entry-plane" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  tags = [ "observability" ];

  endpoints.uptime = {
    port = 8082;
    exposeOnTailnet = true;
    audience = "operator";
    dashboard = {
      title = "Gatus";
      icon = "sh:gatus";
      group = "Admin";
      description = "Service uptime + alerts";
    };
  };
}
