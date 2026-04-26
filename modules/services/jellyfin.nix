{ config, lib, pkgs, ... }:

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
  # config is in backup-restic.nix (or will be when added) — for now
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
  # specific paths Jellyfin should see back in. ProtectHome=yes also
  # hides /home and /root (the upstream module doesn't set this).
  #
  # Adjust BindReadOnlyPaths if Jellyfin needs more later (e.g. you
  # add a dedicated music library at /mnt/media/music — already covered
  # by the /mnt/media bind).
  systemd.services.jellyfin.serviceConfig = {
    ProtectHome = "yes";
    TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
    BindReadOnlyPaths = [
      "/mnt/media"
      "/srv/share"
    ];
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8096 ];

  # Exposed at https://media.nori.lan via Caddy. Auto-monitored by
  # Gatus (default HTTP probe to /).
  nori.lanRoutes.media = {
    port = 8096;
    monitor = { };
  };
}
