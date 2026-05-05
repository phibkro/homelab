{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Jellyfin: media streaming server, tailnet-only.
  #
  # Reads media from /mnt/media/streaming and /mnt/media/home-videos
  # (configured later via Jellyfin's web UI: Dashboard → Libraries
  # → Add). Add the jellyfin user to the `users` group so it can read
  # the nori:users-owned media tree.
  #
  # Per DESIGN tier table, Jellyfin's database is re-derivable from
  # the media library (just media metadata + watch progress + user
  # accounts). Not in scope for off-site backup; Pattern A daily to
  # Pi-or-Hetzner is enough as a fast restore convenience. Backup
  # config is in backup/restic.nix (or will be when added) — for now
  # nothing valuable to lose.
  #
  # First-time setup: connect to
  #   http://nori-station.saola-matrix.ts.net:8096
  # …walk through the wizard (admin user, library paths, transcoding
  # preferences). The admin user is independent of the system `nori`
  # user.
  #
  # Hardware transcoding via the RTX 5060 Ti is supported via NVENC
  # but requires explicit Jellyfin configuration in the web UI
  # (Dashboard → Playback → Hardware acceleration → Nvidia NVENC,
  # then reload). NixOS module exposes the GPU automatically since
  # the nvidia driver is loaded host-wide.

  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  # /mnt/media/* is owned nori:users; the jellyfin service user needs
  # group membership to read it.
  users.users.jellyfin.extraGroups = [ "users" ];

  # Tighten Jellyfin's mount namespace beyond the upstream module's
  # default hardening. Without this, the in-app folder picker can
  # browse the entire host filesystem (read-only, but still leaky).
  #
  # Strategy: tmpfs over /mnt and /srv, then bind-mount only the
  # specific paths Jellyfin should see back in (read-only — Jellyfin
  # never writes to /mnt/media). ProtectHome=mkForce true also hides
  # /home and /root (the upstream module doesn't set this).
  #
  # The /mnt/media parent is bound rather than enumerating per-subvol
  # because Jellyfin's library config in the web UI references paths
  # under /mnt/media/{streaming,home-videos,...} — needs the parent
  # visible so the in-app folder picker walks the tree. Adding a new
  # media subvolume in nori.fs becomes available to Jellyfin
  # automatically, no harden update.
  nori.harden.jellyfin.readOnlyBinds = [
    "/mnt/media"
    config.nori.fs.share.path
  ];

  # Exposed at https://media.nori.lan via Caddy (default-deny on
  # tailnet — Caddy is the only entry point). Auto-monitored by Gatus
  # (default HTTP probe to /). Listed on the home.nori.lan dashboard
  # via the `dashboard` block.
  nori.lanRoutes.media = {
    port = 8096;
    monitor = { };
    dashboard = {
      title = "Jellyfin";
      icon = "si:jellyfin";
      group = "Consume";
      description = "Movies, shows, music — server-rendered";
    };
  };

  # Pattern A — library scan, watch progress, user accounts. The
  # library can be re-derived from media files on disk, but watch
  # history is irreplaceable convenience data. Largest of the
  # service-state repos at ~210MB.
  nori.backups.jellyfin.paths = [ "/var/lib/jellyfin" ];
}
