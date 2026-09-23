{
  active = true;
  kind = "service";
  hostRoles = [ "appliance" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "entry-plane" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  tags = [
    "family-tier"
    "stateless"
  ];

  endpoints.home = {
    port = 8086;
    exposeOnTailnet = true;
    monitor = { };
    audience = "public";
  };
}
