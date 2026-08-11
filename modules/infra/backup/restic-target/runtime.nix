{
  lib,
  pkgs,
  ...
}:

let
  /*
    sshd's ChrootDirectory must be root-owned and not group/other-
    writable — the ext4 mount root satisfies that for free (root:root
    0755 from mkfs), which is precisely why the chrooted `restic` user
    can NOT create anything directly inside it.
  */
  chrootRoot = "/mnt/backup";

  /*
    So per-job repos live one level down, in a directory the SFTP user
    OWNS. That's what makes `initialize = true` work unattended for a
    NEW nori.backups job: restic mkdirs `<repoBase>/<job>/` itself.
    Parking repos at the chroot root instead made every first push fail
    with `MkdirAll /<job>/index: permission denied` — see
    docs/reports/20260811-030203-restic-backups-herdr-projects-mcp-onetouch-failure.md.
  */
  repoBase = "${chrootRoot}/repos";
in
{
  /**
    Restic backup target — chrooted SFTP-only user.

    Lets remote hosts (workstation, future pi/pavilion) push restic
    snapshots to this host's OneTouch drive. The `restic` user has no
    shell, no port forwarding, and an OpenSSH ChrootDirectory locking
    them to /mnt/backup. Repository paths in the workstation's
    `nori.backupTargets.onetouch.repository` string look like
    `sftp:restic@<host>:/repos/<jobname>` — the leading slash is the
    chroot root, i.e. /mnt/backup/repos/<jobname> on the real fs.

    Ownership, and why the extra level exists:

      /mnt/backup         root:root 0755  chroot root (sshd's rule)
      /mnt/backup/repos   restic:restic   repo base — restic writes here
      /mnt/backup/repos/<job>             one restic repo per job

    Aurora's OWN backups (nori.backupTargets.onetouch on aurora, a
    local path) run as root and are unaffected by this split.
  */

  /*
    The repo base, created on the drive itself: the path lookup goes
    through the OneTouch's x-systemd.automount, which mounts it on
    demand. Drive detached → the automount point still masks the
    underlying root-fs directory, so tmpfiles errors instead of
    seeding a shadow repo base on aurora's SSD.
  */
  systemd.tmpfiles.rules = [
    "d ${repoBase} 0750 restic restic -"
  ];

  users.users.restic = {
    isSystemUser = true;
    group = "restic";
    home = chrootRoot;
    createHome = false; # the ext4 mountpoint; repos/ comes from tmpfiles above
    shell = "${pkgs.shadow}/bin/nologin";
    openssh.authorizedKeys.keys = [
      /*
        workstation→aurora restic SFTP. Private half lives in
        workstation's sops at secrets/secrets.yaml under
        `restic-ssh-key`. Regenerate by re-running `ssh-keygen
        -t ed25519 -f <tmp> -N "" -C "workstation→aurora restic SFTP"`
        and rotating both halves.
      */
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGCigbRnMBopyOyvUoePRO1qMIqgKgH8a0zqt/2rGAaZ workstation→aurora restic SFTP"
    ];
  };
  users.groups.restic = { };

  /*
    `lib.mkAfter` is load-bearing: OpenSSH Match blocks extend to the
    next Match or EOF, swallowing any directive after them. Without
    mkAfter, programs.rust-motd's trailing `PrintLastLog no` (default
    order) lands inside this Match block — and PrintLastLog isn't
    allowed in Match scope, so `sshd -t` rejects the config and the
    system.checks.check-sshd-config build fails. mkAfter pushes this
    block to order 1500 so PrintLastLog stays in global scope above.
  */
  services.openssh.extraConfig = lib.mkAfter ''
    Match User restic
      ChrootDirectory ${chrootRoot}
      ForceCommand internal-sftp -d /
      AllowTcpForwarding no
      X11Forwarding no
      PermitTunnel no
      AllowAgentForwarding no
      PasswordAuthentication no
  '';

  /*
    No service state of its own — the authorized_keys + Match block
    are declarative, the snapshot data is the remote restic clients'
    repos that already get their own backup units.
  */
  nori.backups.restic-target.skip = "Declarative auth + sshd config; snapshot payloads are remote-client repos with their own backup intent.";

  /*
    No systemd unit named `restic-target` — the Match block lives in
    sshd's config, not its own service. Hardening intent recorded
    against the OpenSSH unit by `services.openssh` itself; nothing
    extra to assert here.
  */
  nori.harden.restic-target = { };
}
