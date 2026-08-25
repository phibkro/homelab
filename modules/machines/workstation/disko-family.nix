_: {
  /*
    ── nori.fs declarations ───────────────────────────────────────────
    Workstation-side family-tier locations. These are the canonical
    paths for irreplaceable family data on the Toshiba family vault,
    mounted at /mnt/family/<X>.

    `nori.fs` entries appear here so service modules (Immich, Calibre-web,
    Komga, Navidrome, Samba) read `config.nori.fs.<X>.path` from the
    same declaration as the physical disk layout.
  */
  nori.fs = {
    /*
      `samba = { }` blocks emit per-fs SMB shares via the generator in
      modules/infra/storage/default.nix. Family clients hit
      smb://workstation/<share> over the LAN/tailnet firewall policy.
      `ownerTmpfilesRule = false` on library + archive because
      workstation/default.nix pins them root:media at 02775 for
      calibre-web + komga; a second `nori users` rule would race.
    */
    photos = {
      path = "/mnt/family/photos";
      tier = "irreplaceable";
      samba = { };
    };
    home-videos = {
      path = "/mnt/family/home-videos";
      tier = "irreplaceable";
      samba = { };
    };
    projects = {
      path = "/mnt/family/projects";
      tier = "irreplaceable";
      samba = { };
    };
    library = {
      path = "/mnt/family/library";
      tier = "irreplaceable";
      samba.ownerTmpfilesRule = false;
    };
    archive = {
      path = "/mnt/family/archive";
      tier = "irreplaceable";
      samba.ownerTmpfilesRule = false;
    };
  };

  /*
    Declarative partition layout for workstation's Toshiba HDD — the
    family vault. The physical drive moved here unchanged; this module
    preserves its by-id identity, btrfs filesystem, and subvolume names.
    The format itself is operator-triggered and WIPES the drive:

      nix run github:nix-community/disko/latest -- \
        --mode disko modules/machines/workstation/disko-family.nix

    nofail on every subvolume makes importing this module safe before
    a disko apply — boot keeps going if a subvolume is not present yet.
    `x-systemd.automount` keeps the lazy-mount behavior used by the
    OneTouch module; mounts activate on first access and can be released
    when idle.
  */

  disko.devices = {
    disk.family-vault = {
      type = "disk";
      device = "/dev/disk/by-id/ata-TOSHIBA_MQ01ABD100_66NHP4MFT";
      content = {
        type = "gpt";
        partitions = {
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "family-vault"
                "-f"
              ];

              subvolumes = {
                "@photos" = {
                  mountpoint = "/mnt/family/photos";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                    "nofail"
                  ];
                };
                "@home-videos" = {
                  mountpoint = "/mnt/family/home-videos";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                    "nofail"
                  ];
                };
                "@projects" = {
                  mountpoint = "/mnt/family/projects";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                    "nofail"
                  ];
                };
                "@library" = {
                  mountpoint = "/mnt/family/library";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                    "nofail"
                  ];
                };
                "@archive" = {
                  mountpoint = "/mnt/family/archive";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                    "nofail"
                  ];
                };
                "@snapshots" = {
                  mountpoint = "/mnt/family/.snapshots";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                    "nofail"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}
