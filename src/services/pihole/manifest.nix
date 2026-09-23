# Production Pi DNS is owned by Ansible; this manifest supplies its compiled ports and probes.
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
  tags = [ "network-appliance" ];
  recovery = {
    model = "filesystem";
    backupJob = "pihole";
  };

  listeners.dns.port = 53;
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
    listener = "dns";
    interval = "60s";
    conditions = [ "[CONNECTED] == true" ];
  };
}
