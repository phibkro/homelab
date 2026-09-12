{
  config,
  lib,
  pkgs,
  ...
}:
let
  backup = config.nori.inventory.backup;
  target = backup.pi;
  root = "${backup.mountPoint}/${target.directory}";
in
{
  config = lib.mkIf backup.enabled {
    # Only the Pi's namespace is visible through this account. Its private
    # credential must be verified against inventory's public key before rollout.
    users.users.${target.user} = {
      isSystemUser = true;
      group = target.user;
      home = root;
      createHome = false;
      shell = "${pkgs.shadow}/bin/nologin";
      openssh.authorizedKeys.keys = [ target.authorizedKey ];
    };
    users.groups.${target.user} = { };

    services.openssh.extraConfig = lib.mkAfter ''
      Match User ${target.user}
        ChrootDirectory ${root}
        ForceCommand internal-sftp -d /
        DisableForwarding yes
        PermitTTY no
        PasswordAuthentication no
    '';

    # Never use global tmpfiles here: they could create a writable repository
    # on the root disk when the backup filesystem is absent.
    # The chroot is created only on the mounted destination.
    systemd.services.restic-target-directories = {
      description = "Provision Pi backup repositories on mounted backup filesystem";
      wantedBy = [ "multi-user.target" ];
      before = [ "sshd.service" ];
      unitConfig = {
        RequiresMountsFor = [ backup.mountPoint ];
        AssertPathIsMountPoint = backup.mountPoint;
      };
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg backup.mountPoint}
        ${pkgs.coreutils}/bin/install -d -m 0755 -o root -g root ${lib.escapeShellArg root}
        ${lib.concatMapStringsSep "\n" (job: ''
          ${pkgs.coreutils}/bin/install -d -m 0700 -o ${target.user} -g ${target.user} ${lib.escapeShellArg "${root}/${job.name}"}
        '') target.jobs}
        # Existing OneTouch repositories can predate a recreated receiver
        # account. Reconcile the dedicated Pi namespace contents so the
        # restricted SFTP account can read its immutable Restic objects.
        # The chroot root itself must stay root-owned and non-writable, an
        # OpenSSH invariant enforced before internal-sftp starts.
        ${pkgs.findutils}/bin/find ${lib.escapeShellArg root} -mindepth 1 -exec ${pkgs.coreutils}/bin/chown ${target.user}:${target.user} {} +
      '';
    };

    nori.backups.restic-target.skip = "Declarative SFTP configuration; payloads belong to Pi backup jobs.";
    nori.harden.restic-target = { };
  };
}
