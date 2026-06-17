{
  config,
  lib,
  ...
}:

lib.mkMerge [
  { nori.services.samba.tags = [ "network-appliance" ]; }
  (lib.mkIf config.nori.services.samba.enabled {
    /**
      Samba server, tailnet-only.

      Shares — one declared here (whole-drive `media`), two derived
      from nori.fs entries via modules/infra/storage/default.nix:
        media → /mnt/media   (whole IronWolf btrfs root; subvolumes visible
                               as subdirs: streaming, photos, home-videos,
                               projects). Hardcoded here because the share
                               covers the btrfs root, which isn't a single
                               nori.fs subvol entry.
        share → /srv/share   (emitted by nori.fs.share.samba — declared
                               alongside disko at machines/workstation/disko.nix)
        nori  → /srv/nori    (emitted by nori.fs.nori.samba — recursive
                               dotfile veto declared alongside disko)

      Auth: smbpasswd-managed, separate from system passwords. After
      first rebuild, on the host:
        sudo smbpasswd -a nori

      Exposure: openFirewall = false. The firewall opens SMB only on
      tailscale0 (per NETWORK.md § zones). `hosts allow`/`hosts deny`
      adds defense-in-depth at the smbd layer.

      Single-user assumption: nori is the only valid user on all shares.
      Force user/group means writes always land as nori:users regardless
      of which client created them — keeps perms consistent for any
      service that later reads the same path (Jellyfin, Immich, etc.).

      Immich vs Samba separation on /mnt/media/photos is intentional, not
      a sync issue — Immich owns the immich library subdir; Samba exposes
      the rest for direct file access.
    */

    services.samba = {
      enable = true;
      openFirewall = false;

      /*
        NetBIOS name service (nmbd) and winbind are for Windows Network
        Neighborhood discovery and AD integration — not needed for
        tailnet-only access where clients connect by hostname/IP.
      */
      nmbd.enable = false;
      winbindd.enable = false;

      settings = lib.mkMerge [
        {
          global = {
            "workgroup" = "WORKGROUP";
            "server string" = config.networking.hostName;
            "security" = "user";
            "map to guest" = "Never";
            "guest account" = "nobody";

            /*
              Defense-in-depth: only Tailscale-range IPs may connect even
              if the firewall ever opens 445 elsewhere by accident.
              100.64.0.0/10 is the CGNAT range Tailscale assigns from.
            */
            "hosts allow" = "100.64.0.0/10 127.0.0.1 ::1 fd7a:115c:a1e0::/48";
            "hosts deny" = "0.0.0.0/0";

            /*
              macOS interop (Finder thumbnails, .DS_Store handling, resource
              forks). Without these the Mac client works but spams unwanted
              AppleDouble files (._*) all over the share.
            */
            "vfs objects" = "catia fruit streams_xattr";
            "fruit:metadata" = "stream";
            "fruit:model" = "MacSamba";
            "fruit:posix_rename" = "yes";
            "fruit:veto_appledouble" = "no";
            "fruit:nfs_aces" = "no";
            "fruit:wipe_intentionally_left_blank_rfork" = "yes";
            "fruit:delete_empty_adfiles" = "yes";
          };

          /**
            `share`/`nori`/family-tier shares emitted by
            modules/infra/storage/default.nix from the per-fs `samba = { … }`
            blocks declared next to disko on each host.
          */
        }

        /*
          Workstation-only `media` share — covers the IronWolf btrfs
          ROOT (not a single nori.fs subvol), so it lives here as a
          one-off rather than going through the per-fs generator. Gate
          on the workstation-shape nori.fs entries so aurora (which has
          no `downloads`/`photos@/mnt/media/...`) doesn't try to expose
          a path that doesn't exist.
        */
        (lib.mkIf (config.nori.fs ? downloads) {
          "media" = {
            path = "/mnt/media";
            browseable = "yes";
            "read only" = "no";
            "valid users" = "nori";
            "force user" = "nori";
            "force group" = "users";
            "create mask" = "0664";
            "directory mask" = "0775";
          };
        })
      ];
    };

    # Open SMB only on the tailnet interface.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 445 ];

    /*
      Ownership tmpfiles for the subvols accessed via the workstation
      `media` SMB share. Per-fs `samba = { … }` blocks emit their own
      tmpfiles via modules/infra/storage/default.nix; the four below cover the
      subvols exposed transitively by the whole-drive media share.

      Enumerated, not auto-derived: @library and @archive are also
      under /mnt/media but are owned root:media by arr/shared.nix
      tmpfiles (mode 02775), so a tmpfiles rule here with `nori users`
      would conflict.

      Same workstation-only gate as the `media` share above.
    */
    systemd.tmpfiles.rules = lib.optionals (config.nori.fs ? downloads) [
      "d ${config.nori.fs.downloads.path}   0775 nori users -"
      "d ${config.nori.fs.photos.path}      0775 nori users -"
      "d ${config.nori.fs.home-videos.path} 0775 nori users -"
      "d ${config.nori.fs.projects.path}    0775 nori users -"
    ];

    /**
      Config declarative in Nix; the actual share data is /mnt/media
      (covered by media-irreplaceable) and /srv/share (covered by
      user-data). Samba's state at /var/lib/samba is just runtime
      session caches.
    */
    nori.backups.samba.skip = "Config declarative; share data covered by media-irreplaceable + user-data.";
  })
]
