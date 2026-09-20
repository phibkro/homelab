# Production Pi DNS is owned by Ansible; Nix Blocky is a test adapter.
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
  tags = [ "network-appliance" ];
  endpoints.pihole = {
    port = 8081;
    noAuthReason = "Pi-hole provides its own administrator authentication.";
    monitor = {
      name = "pihole-admin";
      path = "/admin/";
      interval = "60s";
      conditions = [ "[STATUS] == 200" ];
    };
  };
  _probes.pihole-dns = {
    scheme = "tcp";
    port = 53;
    interval = "60s";
    conditions = [ "[CONNECTED] == true" ];
  };
}
