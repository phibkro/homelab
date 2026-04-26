{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Samba server, tailnet-only.
  #
  # Two shares:
  #   media → /mnt/media   (whole IronWolf btrfs root; subvolumes visible
  #                          as subdirs: streaming, photos, home-videos,
  #                          projects)
  #   share → /srv/share   (the @srv-share subvolume on root; family-
  #                          shared dumping ground per DESIGN access matrix)
  #
  # Auth: smbpasswd-managed, separate from system passwords. After
  # first rebuild, on the host:
  #   sudo smbpasswd -a nori
  # The Samba password is independent of the Linux login password.
  #
  # Exposure: openFirewall = false. The firewall opens SMB only on
  # tailscale0 (per DESIGN.md L160-166). `hosts allow`/`hosts deny`
  # adds defense-in-depth at the smbd layer.
  #
  # Single-user assumption: nori is the only valid user on both shares.
  # Force user/group means writes always land as nori:users regardless
  # of which client created them — keeps perms consistent for any
  # service that later reads the same path (Jellyfin, Immich, etc.).
  #
  # See learned_gotchas.md re: Immich vs Samba separation on /mnt/media/
  # photos — intentional, not a sync issue.

  services.samba = {
    enable = true;
    openFirewall = false;

    # NetBIOS name service (nmbd) and winbind are for Windows Network
    # Neighborhood discovery and AD integration — not needed for
    # tailnet-only access where clients connect by hostname/IP.
    nmbd.enable = false;
    winbindd.enable = false;

    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "nori-station";
        "security" = "user";
        "map to guest" = "Never";
        "guest account" = "nobody";

        # Defense-in-depth: only Tailscale-range IPs may connect even
        # if the firewall ever opens 445 elsewhere by accident.
        # 100.64.0.0/10 is the CGNAT range Tailscale assigns from.
        "hosts allow" = "100.64.0.0/10 127.0.0.1 ::1 fd7a:115c:a1e0::/48";
        "hosts deny" = "0.0.0.0/0";

        # macOS interop (Finder thumbnails, .DS_Store handling, resource
        # forks). Without these the Mac client works but spams unwanted
        # AppleDouble files (._*) all over the share.
        "vfs objects" = "catia fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:model" = "MacSamba";
        "fruit:posix_rename" = "yes";
        "fruit:veto_appledouble" = "no";
        "fruit:nfs_aces" = "no";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";
        "fruit:delete_empty_adfiles" = "yes";
      };

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

      "share" = {
        path = "/srv/share";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "nori";
        "force user" = "nori";
        "force group" = "users";
        "create mask" = "0664";
        "directory mask" = "0775";
      };
    };
  };

  # Open SMB only on the tailnet interface.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 445 ];

  # btrfs subvolumes created by disko are root:root by default. The
  # Samba shares need nori to be able to write at the subvolume root,
  # not just inside an existing nori-owned subdir. systemd-tmpfiles
  # asserts ownership on activation so this stays correct across
  # rebuilds and (defensively) any future disko re-run.
  systemd.tmpfiles.rules = [
    "d /srv/share             0775 nori users -"
    "d /mnt/media/streaming   0775 nori users -"
    "d /mnt/media/photos      0775 nori users -"
    "d /mnt/media/home-videos 0775 nori users -"
    "d /mnt/media/projects    0775 nori users -"
  ];
}
