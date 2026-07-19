{
  config,
  lib,
  pkgs,
  ...
}:

/**
  Always-on entry-plane policy.

  The profile owns service-facing behavior that should follow the role to a
  replacement appliance. Raspberry Pi kernel/image details remain in the
  physical node realization.
*/

{
  # Serve the inventory-derived DNS map directly rather than forwarding it.
  nori.blocky.role = "self-hosted";

  /*
    Stream Pi service backups to Aurora's OneTouch over chrooted SFTP. The
    `/pi` prefix keeps appliance snapshots out of Workstation's repo namespace.
  */
  sops.secrets.restic-password = {
    owner = "root";
    mode = "0400";
  };
  sops.secrets.restic-ssh-key = {
    owner = "root";
    mode = "0400";
  };
  environment.etc."ssh/aurora_known_hosts".text = ''
    aurora.saola-matrix.ts.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnfMYRv1a3CGvnL0e82w/Z1RK7aOqS3k8JvMYbD8NET
  '';
  nori.backupTargets.onetouch = {
    repository = "sftp:restic@aurora.saola-matrix.ts.net:/pi";
    description = "Entry plane → OneTouch via Aurora SFTP, scoped under /pi/ so appliance snapshots do not collide with Workstation's shared chroot namespace.";
    extraOptions = [
      "sftp.command='${pkgs.openssh}/bin/ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/ssh/aurora_known_hosts -i /run/secrets/restic-ssh-key restic@aurora.saola-matrix.ts.net -s sftp'"
    ];
  };
  systemd.tmpfiles.rules = [ "d /var/backup 0755 root root -" ];

  # Advertise the LAN subnet and optional exit-node service.
  services.tailscale.useRoutingFeatures = lib.mkForce "server";
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    8082 # Gatus web UI on tailnet only
  ];

  # Operator recovery tool: wake Workstation from a phone SSH session.
  environment.systemPackages = [ pkgs.wakeonlan ];

  /*
    Chromecast hardcodes public resolvers. The entry appliance is its exit
    node, so the tailnet-appliance adapter redirects DNS to local Blocky.
  */
  nori.tailnet.appliances.chromecast = {
    tailnetIp = "100.94.135.114"; # lint: skip tailnetIp — appliance identity, not a NixOS host
    interceptedAt = "pi";
  };

  nori.gatusProbes = {
    station-blocky-dns.url = "tcp://${config.nori.lanIp}:53";
    station-ssh.url = "tcp://${config.nori.lanIp}:22";
    station-caddy = {
      url = "https://status.${config.nori.domain}";
      interval = "120s";
      conditions = [ "[STATUS] == 200" ];
    };
    self-blocky-dns.url = "tcp://127.0.0.1:53";
    aurora-ssh.url = "tcp://${config.nori.hosts.aurora.tailnetIp}:22";
    aurora-samba.url = "tcp://${config.nori.hosts.aurora.tailnetIp}:445";
  };
}
