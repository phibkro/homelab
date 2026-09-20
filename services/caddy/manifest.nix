{
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
    "network-appliance"
    "stateful"
  ];
  listenerPorts = {
    http = 80;
    https = 443;
  };
}
