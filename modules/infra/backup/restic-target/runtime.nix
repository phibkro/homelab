{
  lib,
  pkgs,
  ...
}:

{
  /**
    Restic backup target — chrooted SFTP-only user.

    Lets remote hosts (workstation, future pi/pavilion) push restic
    snapshots to this host's /mnt/backup. The `restic` user has no
    shell, no port forwarding, and an OpenSSH ChrootDirectory locking
    them to /mnt/backup. Repository paths in the workstation's
    `nori.backupTargets.onetouch.repository` string look like
    `sftp:restic@<host>:/<jobname>` — the leading slash is the chroot
    root, i.e. /mnt/backup on the real fs.

    The chroot guarantees:
      ChrootDirectory must be owned by root and not group/other-writable.
      Ext4 mount-root inherits root:root 0755 from the filesystem, so
      /mnt/backup satisfies this automatically when the OneTouch is
      mounted.

    ── Adding a job: the per-job dir is an OPERATOR step ──────────────
    The same root-ownership that makes the chroot legal makes the chroot
    root unwritable for the `restic` user, so `initialize = true` CANNOT
    create /mnt/backup/<job> — restic fails with
    `MkdirAll /<job>/… permission denied` and the nightly unit stays red
    until someone acts. Before a new `nori.backups.<job>` fans out to the
    `onetouch` target, on aurora:
      sudo install -d -o restic -g restic /mnt/backup/<job>
    Skip /mnt/backup itself — that must stay root-owned for chroot. Pi
    avoids the step entirely by scoping its repository under a restic-owned
    /pi prefix (modules/profiles/entry-plane.nix); making Workstation do
    the same is the standing fix for the class, and costs a one-time
    relocation of every existing repo on the drive. Bit 2026-08-11 with
    the herdr-projects-mcp job; see
    docs/reports/20260813-030204-restic-backups-herdr-projects-mcp-onetouch-failure.md.
  */

  users.users.restic = {
    isSystemUser = true;
    group = "restic";
    home = "/mnt/backup";
    createHome = false; # /mnt/backup is the ext4 mountpoint
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
      ChrootDirectory /mnt/backup
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
