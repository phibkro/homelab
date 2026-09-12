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
  enabled =
    inputs.self.lib.noriInventory.backup.enabled
    && inputs.self.lib.noriInventory.backup.targetName == "onetouch"
    && inputs.self.lib.noriInventory.backup.mountPoint == "/mnt/backup"
    && ironwolf.role == "cold-primary"
    && ironwolf.attachedHost == "workstation"
    && config.disko.devices.disk.media.device == ironwolf.identity.byId
    && oneTouch.role == "backup"
    && config.nori.inventory.backup.device == oneTouch.filesystem.device
    && config.nori.inventory.backup.fsType == oneTouch.filesystem.type
    && config.services.btrbk.instances.media.settings.snapshot_preserve == "7d 4w 3m"
    && config.nori.inventory.backup.retention.coldMedia.localSnapshotPreserve == "7d 4w 3m"
    &&
      config.nori.inventory.backup.retention.coldMedia.resticPruneOpts == [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 12"
        "--keep-yearly 3"
      ]
    && (config.fileSystems ? "/mnt/backup")
    && (config.nori.backupTargets ? onetouch)
    && config.nori.backupDelivery.enable
    && lib.all (check: check.assertion) config.assertions
    && (config.users.users ? restic)
    && (config.sops.secrets ? restic-password)
    && lib.any scheduledBackup (builtins.attrNames config.systemd.services)
    && lib.any scheduledBackup (builtins.attrNames config.systemd.timers);
  localRollback = config.services.btrbk.instances != { };
in
if enabled && localRollback then
  "ok — OneTouch enabled; independent backup and same-disk rollback retained"
else
  throw "Backup policy mismatch: enabled=${toString enabled}, local rollback=${toString localRollback}"
