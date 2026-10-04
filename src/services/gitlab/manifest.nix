{
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];

  /*
    Placement. GitLab is an application with a database, repository storage
    and long-lived background workers.

    FALLBACK: it runs on the `primary-service-host` (workstation). Its intended
    home is the `application-service-host` (adelie): a host without a desktop
    session, GPU job or agent fleet, beside the other PostgreSQL-backed
    applications, where a restore never depends on the machine that holds the
    live data. Adelie is offline, and the operator authorized this placement on
    2026-10-04. Workstation carries the load whose swap pressure and oomd kill
    are recorded in docs/archive/reports/2026-07-20-oomd-agent-fleet-kill.md,
    so GitLab shares memory with the desktop and the agent fleet there.

    Move it back with the steps in docs/runbooks/gitlab-authority.md § Moving
    GitLab to another host. The first step is this selector: use the tag
    `application-service-host`. The Pi is not an option: it is an appliance
    with SD storage and no local restic target.
  */
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "primary-service-host" ]; } ];
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
