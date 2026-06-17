_: {
  /*
    ── nori.fs declarations ───────────────────────────────────────────
    Aurora-side family-tier locations. Mirrors the irreplaceable-tier
    entries that live on workstation (modules/machines/workstation/disko-media.nix),
    but at /mnt/family/<X> instead of /mnt/media/<X>. Co-existence
    during P6-P11 is fine: each host evals independently, no cross-host
    conflict. The data move from workstation to aurora happens in P10.

    Why nori.fs entries appear here even before the data is present:
    later phases want service modules (Immich, Calibre-web, Komga,
    Navidrome, Samba) to read `config.nori.fs.<X>.path` on aurora once
    they migrate; declaring the entries up front means a service move
    is just a `nori.services.<svc>.enable = true` on aurora.
  */
  nori.fs = {
    /*
      `samba = { }` blocks emit per-fs SMB shares via the generator in
      modules/infra/storage/default.nix. Family clients hit smb://aurora/<share>
      over the tailnet (default-deny LAN; samba.nix opens 445 only on
      tailscale0). Share names match the workstation-side naming so a
      family bookmark only needs the hostname swapped. `ownerTmpfilesRule
      = false` on library + archive because aurora's tmpfiles already pin
      them root:media at 02775 (modules/machines/aurora/default.nix) for
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
    Declarative partition layout for aurora's Toshiba HDD — the family
    vault. P6 lands the declaration; the format itself is operator-
    triggered (it WIPES the drive):

      nix run github:nix-community/disko/latest -- \
        --mode disko modules/machines/aurora/disko-family.nix

    Pre-disko-apply state: GPT with sdb1 (2G) + sdb2 (929.5G) leftovers
    from this laptop's prior life. Wipe-OK (operator confirmed in the
    P6 design call). Service-state overflow (postgres etc.) for the
    eventual migrated services is intentionally NOT carved here — the
    SSD-vs-HDD choice for service state is the "Still open" decision
    in the migration plan; defer until first service move measures it.

    nofail on every subvolume so the import in modules/machines/aurora/default.nix
    is safe BEFORE the disko apply — boot keeps going even when the
    subvols don't exist yet. Same `x-systemd.automount` pattern used by
    disko-onetouch.nix; lazy-mount means the subvol mounts on first
    access, can be unmounted when idle.
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
