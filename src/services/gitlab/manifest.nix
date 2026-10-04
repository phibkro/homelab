{
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];

  /*
    Placement. GitLab is an SSD-local application with a database, repository
    storage and long-lived background workers: the `application-service-host`
    duty. Adelie holds it (NVMe system disk, 6 cores, 32 GB) beside the other
    PostgreSQL-backed applications and the restic-over-SFTP delivery to the
    OneTouch disk, so a restore never depends on the machine that holds the
    live data. The workstation is the other workhorse, but it carries the
    desktop, media, GPU and agent-fleet load whose swap pressure and oomd kill
    are recorded in docs/archive/reports/2026-07-20-oomd-agent-fleet-kill.md;
    the Pi is an appliance with SD storage and no local restic target. Adelie
    also carries the graphical-desktop profile for remote sessions, so its
    memory is shared; see the resource reasoning in nixos.nix.
  */
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "application-service-host" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ./nixos.nix;
  tags = [
    "operator-tier"
    "stateful"
  ];

  /*
    `gitlab:backup:create` exports the database and every repository into one
    archive. The restic job named here copies that archive to the OneTouch.
  */
  recovery = {
    model = "application-export";
    backupJob = "gitlab";
  };

  /*
    Authority plane: deliberately no `endpoints`. An endpoint projects a Pi
    Caddy route, a Pi-hole record and a Gatus probe, which would reach every
    LAN client. The private listener only reserves the port in the collision
    check. The runtime binds it to loopback and the host's tailnet address and
    opens it on tailscale0 alone.
  */
  listeners.http.port = 8929;
}
