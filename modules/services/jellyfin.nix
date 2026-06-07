{
  config,
  ...
}:

{
  # Jellyfin — media streaming server. Library paths configured via
  # web UI (Dashboard → Libraries → Add).
  #
  # First-time setup: connect to
  #   http://workstation.saola-matrix.ts.net:8096
  # …walk through the wizard. Admin user is independent of the
  # system `nori` user.
  #
  # NVENC on the RTX 5060 Ti works but requires opt-in via web UI
  # (Dashboard → Playback → Hardware acceleration → Nvidia NVENC,
  # then reload). The host-wide nvidia driver exposes the GPU
  # automatically; no module-level switch.

  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  # /mnt/media/* is owned nori:users — group membership grants read.
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

  nori.lanRoutes.media = {
    port = 8096;
    monitor = { };
    audience = "family";
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
  nori.backups.jellyfin.include = [ "/var/lib/jellyfin" ];
}
