{ inputs, lib, ... }:
let
  config = inputs.self.nixosConfigurations.workstation.config;
  scheduledBackup =
    name:
    lib.any (prefix: lib.hasPrefix prefix name) [
      "restic-backups-"
      "restic-check-"
      "restore-drill-"
      "restic-target"
    ];
  disabled =
    !inputs.self.lib.noriInventory.backup.enabled
    && inputs.self.lib.noriInventory.backup.targetName == "onetouch"
    && inputs.self.lib.noriInventory.backup.mountPoint == "/mnt/backup"
    && !(config.fileSystems ? "/mnt/backup")
    && config.nori.backupTargets == { }
    && !config.nori.backupDelivery.enable
    && lib.all (check: check.assertion) config.assertions
    && config.services.restic.backups == { }
    && !(config.users.users ? restic)
    && !(config.sops.secrets ? restic-password)
    && !lib.any scheduledBackup (builtins.attrNames config.systemd.services)
    && !lib.any scheduledBackup (builtins.attrNames config.systemd.timers);
  localRollback = config.services.btrbk.instances != { };
in
if disabled && localRollback then
  "ok — OneTouch prepared but disabled; same-disk rollback snapshots retained"
else
  throw "Backup policy mismatch: disabled=${toString disabled}, local rollback=${toString localRollback}"
