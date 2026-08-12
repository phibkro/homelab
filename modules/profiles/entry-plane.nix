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

let
  site = import ../../inventory/site.nix;
  hostProfiles = config.nori.inventory.hosts.${config.networking.hostName}.profiles;
  needsApplianceBackupTarget = !lib.elem "backup-source" hostProfiles;
in
{
  # Serve the inventory-derived DNS map directly rather than forwarding it.
  nori.blocky.role = "self-hosted";

  /*
    Stream appliance service backups to Aurora's OneTouch over chrooted SFTP,
    scoped under this host's own namespace directory. Same construction every
    pusher uses now — Aurora creates one restic-owned namespace per host in
    `nori.hosts` (the restic-target workload), which is what makes a NEW job's
    `initialize = true` able to mkdir its repo at all.
  */
  sops.secrets = lib.mkIf needsApplianceBackupTarget {
    restic-password = {
      owner = "root";
      mode = "0400";
    };
    restic-ssh-key = {
      owner = "root";
      mode = "0400";
    };
  };
  environment.etc."ssh/aurora_known_hosts" = lib.mkIf needsApplianceBackupTarget {
    text = ''
      aurora.saola-matrix.ts.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnfMYRv1a3CGvnL0e82w/Z1RK7aOqS3k8JvMYbD8NET
    '';
  };
  nori.backupTargets.onetouch = lib.mkIf needsApplianceBackupTarget {
    repository = "sftp:restic@aurora.saola-matrix.ts.net:/${config.networking.hostName}";
    description = "Entry plane → OneTouch via Aurora SFTP, scoped under /${config.networking.hostName}/ so appliance snapshots get their own writable repo namespace and cannot collide with another host's job names.";
    extraOptions = [
      "sftp.command='${pkgs.openssh}/bin/ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/ssh/aurora_known_hosts -i /run/secrets/restic-ssh-key restic@aurora.saola-matrix.ts.net -s sftp'"
    ];
  };
  systemd.tmpfiles.rules = lib.mkIf needsApplianceBackupTarget [ "d /var/backup 0755 root root -" ];

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
    interceptedAt = site.entryPlaneHost;
  };

  nori.gatusProbes = {
    station-blocky-dns.url = "tcp://${config.nori.lanIp}:53";
    station-ssh.url = "tcp://${config.nori.lanIp}:22";
    station-caddy = {
      url = "https://uptime.${config.nori.domain}";
      interval = "120s";
      conditions = [ "[STATUS] == 200" ];
    };
    self-blocky-dns.url = "tcp://127.0.0.1:53";
    aurora-ssh.url = "tcp://${config.nori.hosts.aurora.tailnetIp}:22";
    aurora-samba.url = "tcp://${config.nori.hosts.aurora.tailnetIp}:445";
  };
}
