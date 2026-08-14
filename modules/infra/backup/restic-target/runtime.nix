{
  config,
  lib,
  pkgs,
  ...
}:

let
  /*
    One namespace per remote client, named after the client's own
    hostname — the same string the client derives on its side
    (`nori.backupTargets.onetouch.repository` in
    modules/infra/backup/restic.nix and modules/profiles/entry-plane.nix
    both interpolate `config.networking.hostName`). Generated from the
    inventory rather than hand-listed so onboarding a pushing host is
    a no-op here; an unused namespace costs one empty 0700 dir.

    This host is excluded: its own restic jobs write /mnt/backup
    directly as root, not through the chroot.
  */
  remoteClients = lib.filter (host: host != config.networking.hostName) (
    lib.attrNames config.nori.inventory.hosts
  );
in
{
  /**
    Restic backup target — chrooted SFTP-only user.

    Lets remote hosts (workstation, pi, future pavilion) push restic
    snapshots to this host's /mnt/backup. The `restic` user has no
    shell, no port forwarding, and an OpenSSH ChrootDirectory locking
    them to /mnt/backup. Repository paths in a client's
    `nori.backupTargets.onetouch.repository` string look like
    `sftp:restic@<host>:/<client>` — the leading slash is the chroot
    root, i.e. /mnt/backup on the real fs — and each per-job repo
    lands at `/<client>/<jobname>`.

    The chroot constrains the layout:
      ChrootDirectory must be owned by root and not group/other-writable.
      Ext4 mount-root inherits root:root 0755 from the filesystem, so
      /mnt/backup satisfies this automatically when the OneTouch is
      mounted — and the `restic` user consequently can NEVER create a
      directory at the chroot root. That is why clients push into a
      restic-owned per-host namespace (the tmpfiles rules below):
      restic's `initialize = true` creates /<client>/<job> inside a
      namespace it owns, so a newly declared nori.backups.<job> needs
      no aurora-side step. Pushing to the bare chroot root instead
      made every new job fail its first push
      ("MkdirAll /<job>/snapshots: permission denied") — see
      docs/reports/20260814-030203-restic-backups-herdr-projects-mcp-onetouch-failure.md.

    ── Migrating repos into a namespace (one-time, per client) ───────
    Repos that predate the client's namespace sit at the chroot root.
    Move them in before the client rebuilds, or the client will
    silently initialize empty repos and orphan its snapshot history:
      sudo mv /mnt/backup/{<job1>,<job2>,...} /mnt/backup/<client>/
      sudo chown -R restic:restic /mnt/backup/<client>
    Skip /mnt/backup itself — that must stay root-owned for chroot.
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
    The writable half of the chroot. /mnt/backup itself stays
    root:root 0755 (sshd's requirement); these per-client dirs are
    restic-owned, so the SFTP client can create its own per-job repos
    inside one. 0700 — no other user on this host has business in a
    remote client's repo namespace.

    /mnt/backup is an x-systemd.automount mount (disko-onetouch.nix),
    so tmpfiles touching these paths triggers the mount at boot. With
    the automount active and the drive absent, the trigger fails and
    tmpfiles reports the rule rather than silently creating a shadow
    directory under the mountpoint — the drive being gone is a real
    backup-plane signal, not noise to suppress.
  */
  systemd.tmpfiles.rules = map (client: "d /mnt/backup/${client} 0700 restic restic -") remoteClients;

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
