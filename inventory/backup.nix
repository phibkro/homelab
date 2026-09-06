# Planned OneTouch destination. Disabled until physical connection, identity,
# capacity, and recovery checks are approved. Existing archives are preserved.
# Before activation, verify the Pi private credential matches authorizedKey.
{
  enabled = false;
  targetName = "onetouch";
  device = "/dev/disk/by-id/usb-Seagate_One_Touch_HDD_00000000NABNR6G2-0:0-part1";
  fsType = "ext4";
  targetHost = "workstation";
  hostname = "workstation.saola-matrix.ts.net";
  mountPoint = "/mnt/backup";
  pi = {
    user = "restic";
    directory = "pi";
    repositoryPrefix = "";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFYfsviUipugcpG8pMGtNh4C6lhm51dTF4uJj+BsuNj";
    authorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGCigbRnMBopyOyvUoePRO1qMIqgKgH8a0zqt/2rGAaZ";
    jobs = [
      {
        name = "pihole";
        paths = [
          "/var/lib/containers/storage/volumes/pihole-data/_data"
          "/opt/pihole/dnsmasq.d/05-homelab-local-records.conf"
        ];
      }
      {
        name = "caddy";
        paths = [
          "/opt/caddy/data"
          "/opt/caddy/config"
        ];
      }
      {
        name = "authelia";
        paths = [
          "/etc/authelia/configuration.yml"
          "/etc/authelia/users_database.yml"
          "/var/lib/authelia"
        ];
      }
      {
        name = "ntfy";
        paths = [
          "/var/cache/ntfy"
          "/var/lib/ntfy"
        ];
      }
      {
        name = "beszel";
        paths = [ "/var/lib/beszel" ];
      }
      {
        name = "victoriametrics";
        paths = [
          "/var/lib/victoriametrics"
          "/etc/victoriametrics"
        ];
      }
      {
        name = "victorialogs";
        paths = [ "/var/lib/victorialogs" ];
      }
      {
        name = "vector";
        paths = [
          "/var/lib/vector"
          "/etc/vector"
        ];
      }
    ];
  };
}
