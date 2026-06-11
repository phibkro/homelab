{ pkgs, ... }:

{
  # Restic backup target — chrooted SFTP-only user.
  #
  # Lets remote hosts (workstation, future pi/pavilion) push restic
  # snapshots to this host's /mnt/backup. The `restic` user has no
  # shell, no port forwarding, and an OpenSSH ChrootDirectory locking
  # them to /mnt/backup. Repository paths in the workstation's
  # `nori.backupTargets.onetouch.repository` string look like
  # `sftp:restic@<host>:/<jobname>` — the leading slash is the chroot
  # root, i.e. /mnt/backup on the real fs.
  #
  # The chroot guarantees:
  #   ChrootDirectory must be owned by root and not group/other-writable.
  #   Ext4 mount-root inherits root:root 0755 from the filesystem, so
  #   /mnt/backup satisfies this automatically when the OneTouch is
  #   mounted. Per-job subdirs (/mnt/backup/<job>) are restic-owned;
  #   restic creates them via `initialize = true` on first push.
  #
  # ── Onboarding existing repos (one-time after the OneTouch moves) ─
  # The drive's existing per-job dirs were created by workstation's
  # root, so they're root:root. Hand ownership to the new restic user
  # so the SFTP client can write:
  #   sudo chown -R restic:restic /mnt/backup/{<job1>,<job2>,...}
  # Skip /mnt/backup itself — that must stay root-owned for chroot.

  users.users.restic = {
    isSystemUser = true;
    group = "restic";
    home = "/mnt/backup";
    createHome = false; # /mnt/backup is the ext4 mountpoint
    shell = "${pkgs.shadow}/bin/nologin";
    openssh.authorizedKeys.keys = [
      # workstation→aurora restic SFTP. Private half lives in
      # workstation's sops at secrets/secrets.yaml under
      # `restic-ssh-key`. Regenerate by re-running `ssh-keygen
      # -t ed25519 -f <tmp> -N "" -C "workstation→aurora restic SFTP"`
      # and rotating both halves.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGCigbRnMBopyOyvUoePRO1qMIqgKgH8a0zqt/2rGAaZ workstation→aurora restic SFTP"
    ];
  };
  users.groups.restic = { };

  services.openssh.extraConfig = ''
    Match User restic
      ChrootDirectory /mnt/backup
      ForceCommand internal-sftp -d /
      AllowTcpForwarding no
      X11Forwarding no
      PermitTunnel no
      AllowAgentForwarding no
      PasswordAuthentication no
  '';

  # No service state of its own — the authorized_keys + Match block
  # are declarative, the snapshot data is the remote restic clients'
  # repos that already get their own backup units.
  nori.backups.restic-target.skip = "Declarative auth + sshd config; snapshot payloads are remote-client repos with their own backup intent.";

  # No systemd unit named `restic-target` — the Match block lives in
  # sshd's config, not its own service. Hardening intent recorded
  # against the OpenSSH unit by `services.openssh` itself; nothing
  # extra to assert here.
  nori.harden.restic-target = { };
}
