{ inputs, lib, ... }:
let
  inventory = inputs.self.lib.noriInventory;
  config = inputs.self.nixosConfigurations.workstation.config;
  ironwolf = inventory.disks."ironwolf-pro";
  oneTouch = inventory.disks."one-touch";
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
    && ironwolf.role == "cold-primary"
    && ironwolf.attachedHost == "workstation"
    && config.disko.devices.disk.media.device == ironwolf.identity.byId
    && oneTouch.role == "backup"
    && config.nori.inventory.backup.device == oneTouch.filesystem.device
    && config.nori.inventory.backup.fsType == oneTouch.filesystem.type
    && config.services.btrbk.instances.media.settings.snapshot_preserve == "2d 2w 2m"
    && config.nori.inventory.backup.retention.coldMedia.localSnapshotPreserve == "2d 2w 2m"
    &&
      config.nori.inventory.backup.retention.coldMedia.resticPruneOpts == [
        "--keep-daily 2"
        "--keep-weekly 2"
        "--keep-monthly 2"
        "--keep-yearly 2"
      ]
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
