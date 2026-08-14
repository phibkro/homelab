{
  config,
  lib,
  pkgs,
  ...
}:

{
  /**
    Restic backup target — chrooted SFTP-only user.

    Lets remote hosts (workstation, pi, future pavilion) push restic
    snapshots to this host's /mnt/backup. The `restic` user has no
    shell, no port forwarding, and an OpenSSH ChrootDirectory locking
    them to /mnt/backup. Repository paths in a client's
    `nori.backupTargets.onetouch.repository` string look like
    `sftp:restic@<host>:/<client-hostname>` — the leading slash is the
    chroot root, i.e. /mnt/backup on the real fs.

    ── Why clients get a per-host namespace directory ───────────────
    OpenSSH requires ChrootDirectory (and every parent) to be owned by
    root and not group/other-writable. /mnt/backup is the ext4 mount
    root, so it inherits root:root 0755 and satisfies that for free —
    which ALSO means the `restic` user cannot create anything at the
    chroot root itself. A client pointed at the bare chroot root can
    therefore never bootstrap a new repo: `initialize = true` dies
    with `MkdirAll /<job>/index: permission denied`, forever, until
    root hand-creates the directory here. That was the 2026-08-11/12
    herdr-projects-mcp failure — see
    docs/reports/20260812-030204-restic-backups-herdr-projects-mcp-onetouch-failure.md.

    So this host pre-creates one restic-owned namespace directory per
    pushing host and clients scope their repository under it. Per-job
    repos land at /mnt/backup/<client>/<job>, which restic creates
    itself. The namespace also stops two hosts that run the same job
    name (caddy, authelia) from racing on one repo — the ad-hoc `/pi`
    prefix added after the 2026-06 migration, generalized.

    Derived from `nori.hosts` so a new host's namespace exists the
    moment it enters the registry. This host is excluded (it writes
    locally, not over SFTP) and so are `agent`-role hosts, where a
    paths-based `nori.backups` is a build error
    (modules/infra/backup/default.nix).

    ── One-time migration — run WITH the deploy of this change ───────
    Workstation's repos predate the namespace and sit directly under
    the chroot root. Move them in, on aurora, before workstation's
    03:00 timers fire; otherwise `initialize = true` silently creates
    empty repos under /mnt/backup/workstation and the history is
    orphaned (not lost — it stays where it is):

      sudo find /mnt/backup -mindepth 1 -maxdepth 1 -type d \
        ! -name lost+found ! -name pi ! -name workstation \
        -exec mv -t /mnt/backup/workstation {} +
      sudo chown -R restic:restic /mnt/backup/workstation

    Verify from workstation — the full history must come back, not a
    single fresh snapshot:

      sudo restic -r sftp:restic@aurora.saola-matrix.ts.net:/workstation/user-data \
        -o sftp.command='...' snapshots | tail
  */

  /*
    Namespace roots for the remote pushers. `d` only creates + chowns;
    it never recurses, so an existing populated namespace is untouched
    on every boot. /mnt/backup is an x-systemd.automount point
    (machines/aurora/disko-onetouch.nix) and automount units are
    established at local-fs.target, before systemd-tmpfiles-setup —
    so this triggers the mount rather than writing a phantom directory
    under it.
  */
  systemd.tmpfiles.rules = map (host: "d /mnt/backup/${host} 0700 restic restic -") (
    lib.attrNames (
      lib.filterAttrs (name: h: name != config.networking.hostName && h.role != "agent") config.nori.hosts
    )
  );

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
