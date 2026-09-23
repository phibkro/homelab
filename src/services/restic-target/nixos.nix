{
  config,
  lib,
  pkgs,
  ...
}:
let
  backup = config.nori.inventory.backup;
  targets = [
    backup.pi
    backup.adelie
  ];
  rootFor = target: "${backup.mountPoint}/${target.directory}";
  writableNames =
    target:
    if target.repositoryPrefix != "" then
      [ target.repositoryPrefix ]
    else
      map (job: job.name) target.jobs;
in
{
  config = lib.mkIf backup.enabled {
    users.users = lib.listToAttrs (
      map (
        target:
        lib.nameValuePair target.user {
          isSystemUser = true;
          group = target.user;
          home = rootFor target;
          createHome = false;
          shell = "${pkgs.shadow}/bin/nologin";
          openssh.authorizedKeys.keys = [ target.authorizedKey ];
        }
      ) targets
    );
    users.groups = lib.listToAttrs (map (target: lib.nameValuePair target.user { }) targets);

    services.openssh.extraConfig = lib.mkAfter (
      lib.concatMapStringsSep "\n" (target: ''
        Match User ${target.user}
          ChrootDirectory ${rootFor target}
          ForceCommand internal-sftp -d /
          DisableForwarding yes
          PermitTTY no
          PasswordAuthentication no
      '') targets
    );

    # Never create receiver directories on the root disk. Each restricted
    # account gets one root-owned chroot and writable descendants only.
    systemd.services.restic-target-directories = {
      description = "Provision restricted backup repositories on the mounted backup filesystem";
      wantedBy = [ "multi-user.target" ];
      before = [ "sshd.service" ];
      unitConfig = {
        RequiresMountsFor = [ backup.mountPoint ];
        AssertPathIsMountPoint = backup.mountPoint;
      };
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg backup.mountPoint}
        ${lib.concatMapStringsSep "\n" (
          target:
          let
            root = rootFor target;
          in
          ''
            ${pkgs.coreutils}/bin/install -d -m 0755 -o root -g root ${lib.escapeShellArg root}
            ${lib.concatMapStringsSep "\n" (
              name:
              "${pkgs.coreutils}/bin/install -d -m 0700 -o ${target.user} -g ${target.user} ${lib.escapeShellArg "${root}/${name}"}"
            ) (writableNames target)}
          ''
        ) targets}
      '';
    };

    nori.backups.restic-target.skip = "Declarative SFTP receiver; payloads belong to remote backup jobs.";
    nori.harden.restic-target-directories.binds = [ backup.mountPoint ];
  };
}
