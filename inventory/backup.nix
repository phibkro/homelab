# OneTouch destination policy. Existing archives are preserved.
# Connection and recovery verification: docs/runbooks/onetouch-backup-cutover.md.
# Before activation, verify the Pi private credential matches authorizedKey.
{
  disks ? import ./disks.nix,
}:
let
  oneTouch = disks."one-touch";
in
{
  enabled = true;
  targetName = "onetouch";
  device = oneTouch.filesystem.device;
  fsType = oneTouch.filesystem.type;
  targetHost = oneTouch.attachedHost;
  hostname = "workstation.saola-matrix.ts.net";
  inherit (oneTouch) mountPoint;
  retention.coldMedia = {
    # Same-disk accidental-deletion rollback, not independent protection.
    localSnapshotPreserve = "7d 4w 3m";
    # Independent OneTouch history, distinct from same-disk rollback above.
    resticPruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 12"
      "--keep-yearly 3"
    ];
  };
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
  adelie = {
    user = "restic-adelie";
    directory = "adelie";
    repositoryPrefix = "repos";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFYfsviUipugcpG8pMGtNh4C6lhm51dTF4uJj+BsuNj";
    authorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILYmfjvN43rLHlfDWGbubLwRlCZLN89/vWkzNcAN5NwI adelie-restic";
  };
}
