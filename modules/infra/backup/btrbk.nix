{
  config,
  lib,
  pkgs,
  ...
}:

let
  /*
    Classify nori.fs paths by their physical btrfs namespace. Family
    paths must never fall through to the root namespace: their source
    filesystem is the Toshiba vault mounted at /mnt/family.
  */
  inherit (config.nori) fs;

  onMedia = _: f: lib.hasPrefix "/mnt/media/" f.path;
  onFamily = _: f: lib.hasPrefix "/mnt/family/" f.path;
  onRoot = n: f: !(onMedia n f) && !(onFamily n f);
  # @downloads is re-derivable; intentionally excluded from snapshots.
  isSnapshotted = _: f: f.tier != "re-derivable";

  rootSubvols = lib.mapAttrs' (_: f: lib.nameValuePair (lib.removePrefix "/" f.path) { }) (
    lib.filterAttrs (n: f: onRoot n f && isSnapshotted n f) fs
  );

  mediaSubvols = lib.mapAttrs' (_: f: lib.nameValuePair (lib.removePrefix "/mnt/media/" f.path) { }) (
    lib.filterAttrs (n: f: onMedia n f && isSnapshotted n f) fs
  );

  familySubvols = lib.mapAttrs' (
    _: f: lib.nameValuePair (lib.removePrefix "/mnt/family/" f.path) { }
  ) (lib.filterAttrs (n: f: onFamily n f && f.tier == "irreplaceable") fs);
in
/*
  Selected only by the Workstation `backup-source` system profile. btrbk
  snapshots the workstation's root, optional non-re-derivable media
  subvolumes, and the family vault; the activation script also enables
  the btrfs quota on /mnt/media/downloads.
*/
{
  /**
    btrbk — local btrfs subvolume snapshots, the "single file
    deletion" recovery path per RECOVERY.md RTO targets (target: <15 min
    to restore an accidentally-deleted file).

    Instances are split by physical btrfs namespace:
      root (SN750):       /home, /srv/share, /var/lib → /.snapshots
      media (IronWolf):   non-re-derivable /mnt/media/* → /mnt/media/.snapshots
      family (Toshiba):   irreplaceable /mnt/family/* → /mnt/family/.snapshots

    The media instance is declared only when nori.fs has a non-re-derivable
    media entry. The family filter is explicit so family paths can never
    become root subvolume names.

    @var/lib is added explicitly because it is a NixOS-managed StateDirectory,
    not a structural FS location. Intentionally excluded:
      @       (system root — covered by NixOS generations)
      @nix    (re-derivable from the flake)
      @downloads (re-derivable — filtered out)

    Retention is conservative for first run; tune per disk growth.
  */
  services.btrbk = {
    instances = {
      root = {
        onCalendar = "daily";
        settings = {
          snapshot_preserve_min = "2d";
          snapshot_preserve = "7d 4w 6m";
          snapshot_dir = ".snapshots";
          timestamp_format = "long";
          volume."/" = {
            /*
              rootSubvols has `home` + `srv/share` from nori.fs (user
              tier). var/lib is a btrfs subvolume but not in nori.fs
              (StateDirectory paths are NixOS-managed, not a structural
              FS location services consume) — added explicitly.
            */
            subvolume = rootSubvols // {
              "var/lib" = { };
            };
          };
        };
      };

      family = {
        onCalendar = "daily";
        settings = {
          snapshot_preserve_min = "2d";
          snapshot_preserve = "14d 8w 12m";
          snapshot_dir = ".snapshots";
          timestamp_format = "long";
          volume."/mnt/family".subvolume = familySubvols;
        };
      };
    }
    // lib.optionalAttrs (mediaSubvols != { }) {
      media = {
        onCalendar = "daily";
        settings = {
          snapshot_preserve_min = "2d";
          snapshot_preserve = "14d 8w 12m";
          snapshot_dir = ".snapshots";
          timestamp_format = "long";
          volume."/mnt/media".subvolume = mediaSubvols;
        };
      };
    };
  };

  # Alert via ntfy template in modules/infra/observability/ntfy/notify.nix.
  systemd.services.btrbk-root.unitConfig.OnFailure = [ "notify@btrbk-root.service" ];
  systemd.services.btrbk-family.unitConfig.OnFailure = [ "notify@btrbk-family.service" ];
  systemd.services.btrbk-family.unitConfig.RequiresMountsFor = [ "/mnt/family" ];
  systemd.services.btrbk-media = lib.mkIf (mediaSubvols != { }) {
    unitConfig.OnFailure = [ "notify@btrbk-media.service" ];
  };

  /*
    ── btrfs qgroup quota on @downloads ────────────────────────────
    Cap @downloads at 3.3 TiB on the IronWolf (3.64 TiB total) to
    prevent the 100%-full metadata-exhaustion wedge pattern (see
    docs/runbooks/storage-full.md). At 100% btrfs can't even reclaim
    via subvolume delete because metadata writes need reserve — that's
    the actual recovery-hostile failure mode, not "disk full" itself.

    With the cap: qBit-as-writer hits ENOSPC on the @downloads quota
    well before the filesystem hits the metadata wall. Recovery path
    stays open (delete from @downloads to free; quota doesn't apply
    to the system pool's metadata budget).

    Headroom math (snapshot 2026-05-16): @downloads = 3.2 TiB on the
    IronWolf, with legacy family copies retained on that filesystem
    but no longer mounted. The 3.3 TiB cap leaves recovery headroom
    for btrfs metadata and the active downloads workload.

    Tune via the 3300G literal below. Adjust upward if the other
    subvols grow such that the budget for @downloads needs to shrink.

    btrfs qgroup overhead: ~5% on metadata-heavy ops (modifying CoW
    ref counts on every write). Acceptable cost for the wedge guard
    on a non-CPU-bound media drive.

    Activation runs on every nixos-rebuild switch. `quota enable` is
    idempotent (no-op if already on). `qgroup limit` overwrites the
    existing limit cleanly. First-time enable triggers a rescan that
    may run for an hour on the multi-TiB filesystem; the limit takes
    effect after rescan completes.

    IMPORTANT — target path: /mnt/media itself is NOT a mountpoint
    (the downloads subvolume mounts directly under it). Targeting
    /mnt/media resolves to the root filesystem (SN750) and enables
    quotas there — wrong FS, expensive. Use /mnt/media/downloads, the
    real IronWolf mountpoint and the subvolume being capped. The family
    namespace is separate at /mnt/family and is not part of this quota.
  */
  system.activationScripts.btrfs-quota-media.text = ''
    if ${pkgs.util-linux}/bin/mountpoint -q /mnt/media/downloads; then
      ${pkgs.btrfs-progs}/bin/btrfs quota enable /mnt/media/downloads >/dev/null 2>&1 || true
      downloads_id=$(${pkgs.btrfs-progs}/bin/btrfs subvolume list /mnt/media/downloads \
        | ${pkgs.gawk}/bin/awk '$NF == "@downloads" { print $2 }')
      if [ -n "$downloads_id" ]; then
        ${pkgs.btrfs-progs}/bin/btrfs qgroup limit 3300G "0/$downloads_id" /mnt/media/downloads \
          || echo "WARNING: failed to set @downloads quota (rescan in progress?)"
      fi
    else
      echo "WARNING: /mnt/media/downloads is not mounted; skipping IronWolf quota setup"
    fi
  '';
}
