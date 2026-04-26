{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Cross-cutting shared resources for the *arr stack — the `media`
  # group + the shared library/download paths under @streaming.
  #
  # Why a dedicated `media` group: Sonarr, Radarr, Bazarr, qBittorrent,
  # and Jellyfin all need read+write to the same paths so that
  # qBittorrent → *arr hardlinks succeed (saves disk + atomic move).
  # btrfs hardlinks across subvolumes don't work, so all of this lives
  # under one subvolume (@streaming). Each service joins the group via
  # `users.users.<svc>.extraGroups = [ "media" ];` in its own module.
  #
  # Layout under /mnt/media/streaming:
  #   movies/                   Radarr library
  #   shows/                    Sonarr library
  #   .downloads/incomplete/    qBittorrent active downloads
  #   .downloads/complete/      qBittorrent finished; *arrs hardlink from here
  #
  # Permissions: directories owned root:media, mode 02775 (setgid + group
  # rwx). The setgid bit means new files inherit `media` as their group,
  # so all stack members can read/write each other's output without
  # umask gymnastics.
  #
  # Jellyfin needs read access too; the existing jellyfin module's user
  # joins `media` via this file rather than each consumer module having
  # to know about jellyfin.

  users.groups.media = { };

  # Jellyfin already exists; fold it into the media group so it can read
  # the libraries the *arrs populate. (qBittorrent + each *arr add their
  # own user to `media` in their respective modules.)
  users.users.jellyfin = lib.mkIf config.services.jellyfin.enable {
    extraGroups = [ "media" ];
  };

  systemd.tmpfiles.rules = [
    "d /mnt/media/streaming                  02775 root media -"
    "d /mnt/media/streaming/movies           02775 root media -"
    "d /mnt/media/streaming/shows            02775 root media -"
    "d /mnt/media/streaming/.downloads       02775 root media -"
    "d /mnt/media/streaming/.downloads/incomplete 02775 root media -"
    "d /mnt/media/streaming/.downloads/complete   02775 root media -"
  ];
}
