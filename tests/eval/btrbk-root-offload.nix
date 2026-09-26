/*
  Workstation root snapshots keep one week on the system NVMe and send
  weekly/monthly history to the IronWolf. Checked on the btrbk settings
  the root.conf is rendered from and on the filesystem that owns the
  target path: /mnt/media itself is a directory on the root btrfs, so a
  target that is not below the IronWolf mount would land on the NVMe.
*/
{ inputs, lib, ... }:
let
  config = inputs.self.nixosConfigurations.workstation.config;
  ironwolf = inputs.self.lib.noriInventory.disks."ironwolf-pro";
  target = "${ironwolf.mountPoint}/.snapshots/workstation-root";
  settings = config.services.btrbk.instances.root.settings;

  # The longest mounted prefix decides which filesystem receives the path.
  mountFor =
    path:
    lib.foldl' (best: m: if lib.stringLength m > lib.stringLength best then m else best) "/" (
      lib.filter (m: lib.hasPrefix "${m}/" path) (lib.attrNames config.fileSystems)
    );
  targetMount = config.fileSystems.${mountFor target};

  retention =
    settings.snapshot_preserve == "7d"
    && settings.snapshot_preserve_min == "2d"
    && !(settings ? target_preserve)
    && !(settings ? target_preserve_min)
    &&
      settings.volume."/".target == {
        ${target} = {
          target_preserve = "4w 6m";
          target_preserve_min = "latest";
        };
      };

  onIronwolf =
    mountFor target == "${ironwolf.mountPoint}/.snapshots"
    && targetMount.fsType == "btrfs"
    && targetMount.device == "/dev/disk/by-partlabel/disk-media-root"
    && lib.elem "subvol=@snapshots" targetMount.options
    && config.disko.devices.disk.media.device == ironwolf.identity.byId;
  mountRequired = lib.elem target config.systemd.services.btrbk-root.unitConfig.RequiresMountsFor;
  rootOnly = lib.elem "d ${target} 0700 root root - -" config.systemd.tmpfiles.rules;
in
if retention && onIronwolf && mountRequired && rootOnly then
  "ok — root snapshots keep 7d locally; 4w 6m history is sent to the IronWolf"
else
  throw ''
    btrbk root offload mismatch:
      local 7d, IronWolf target 4w 6m: ${lib.boolToString retention}
      target on IronWolf @snapshots (${mountFor target}): ${lib.boolToString onIronwolf}
      unit requires target mount: ${lib.boolToString mountRequired}
      target directory root-only: ${lib.boolToString rootOnly}
  ''
