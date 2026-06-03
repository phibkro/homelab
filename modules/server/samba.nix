{
  config,
  ...
}:

{
  # Samba server, tailnet-only.
  #
  # Three shares:
  #   media → /mnt/media   (whole IronWolf btrfs root; subvolumes visible
  #                          as subdirs: streaming, photos, home-videos,
  #                          projects)
  #   share → /srv/share   (the @srv-share subvolume on root; family-
  #                          shared dumping ground / storage per DESIGN matrix)
  #   nori  → /srv/nori    (the @srv-nori subvolume; operator's personal
  #                          networked working dir — separate subvolume so it
  #                          gets its own snapshot/backup tier, NOT mixed into
  #                          the storage share; recursive dotfile veto so
  #                          nested secrets — a project's .env, .git-
  #                          credentials, an .npmrc token — can't be read
  #                          across the tailnet)
  #
  # Auth: smbpasswd-managed, separate from system passwords. After
  # first rebuild, on the host:
  #   sudo smbpasswd -a nori
  # The Samba password is independent of the Linux login password.
  #
  # Exposure: openFirewall = false. The firewall opens SMB only on
  # tailscale0 (per NETWORK.md § zones). `hosts allow`/`hosts deny`
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
        "server string" = "workstation";
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
        inherit (config.nori.fs.share) path;
        browseable = "yes";
        "read only" = "no";
        "valid users" = "nori";
        "force user" = "nori";
        "force group" = "users";
        "create mask" = "0664";
        "directory mask" = "0775";
      };

      # Operator's personal networked working dir. Same tailnet-only,
      # single-user posture as the others, PLUS a recursive dotfile veto:
      # `veto files = /.*/` denies SMB access to any dot-prefixed entry at
      # EVERY depth (not just the top level) — the backstop that keeps a
      # nested secret (a repo's .env, .git-credentials, .npmrc token, a
      # stray ~/.ssh layout) off the tailnet. `delete veto files = yes` so
      # a directory can still be removed despite vetoed dotfiles inside.
      #
      # Limits (by design, not a guarantee): the veto only catches
      # dot-prefixed NAMES — non-dot secret files (credentials.json,
      # kubeconfig, *.key) are NOT hidden, so don't store those here. And
      # it hides .git/.envrc over SMB, which is fine for the local-work +
      # remote-access pattern (you work on workstation; SMB is for reading
      # files from other tailnet devices). Real secrets stay in $HOME
      # (local-only), never relocated here.
      "nori" = {
        inherit (config.nori.fs.nori) path;
        browseable = "yes";
        "read only" = "no";
        "valid users" = "nori";
        "force user" = "nori";
        "force group" = "users";
        "create mask" = "0664";
        "directory mask" = "0775";
        "veto files" = "/.*/";
        "delete veto files" = "yes";
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
  #
  # Enumerated, not auto-derived: @library and @archive are also under
  # /mnt/media but are owned root:media by arr/shared.nix tmpfiles
  # (mode 02775), so a tmpfiles rule here with `nori users` would
  # conflict. Adding a new Samba-writable subvolume = add it here +
  # to nori.fs.
  systemd.tmpfiles.rules = [
    "d ${config.nori.fs.share.path}       0775 nori users -"
    "d ${config.nori.fs.nori.path}        0775 nori users -"
    "d ${config.nori.fs.downloads.path}   0775 nori users -"
    "d ${config.nori.fs.photos.path}      0775 nori users -"
    "d ${config.nori.fs.home-videos.path} 0775 nori users -"
    "d ${config.nori.fs.projects.path}    0775 nori users -"
  ];

  # Config declarative in Nix; the actual share data is /mnt/media
  # (covered by media-irreplaceable) and /srv/share (covered by
  # user-data). Samba's state at /var/lib/samba is just runtime
  # session caches.
  nori.backups.samba.skip = "Config declarative; share data covered by media-irreplaceable + user-data.";
}
