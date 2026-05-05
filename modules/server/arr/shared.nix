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
  # Layout (paths from nori.fs — host's disko config is single source
  # of truth; see modules/effects/fs.nix):
  #   <streaming>/movies/             Radarr library     (re-derivable)
  #   <streaming>/shows/              Sonarr library     (re-derivable)
  #   <streaming>/music/              Lidarr library     (re-derivable)
  #   <streaming>/.downloads/complete qBittorrent finished — same
  #                                    subvol as *arr libraries for the
  #                                    hardlink-on-import flow
  #   <library>/books/                calibre-web library
  #   <library>/comics/               Komga library
  #
  # Note: qBittorrent's INCOMPLETE dir is /var/lib/qBittorrent/incomplete
  # (NVMe @var-lib, not @streaming) — IO isolation. See qbittorrent.nix
  # preStart for the rationale + path config.
  #
  # Permissions: directories owned root:media, mode 02775 (setgid +
  # group rwx). The setgid bit means new files inherit `media` as
  # their group, so all stack members can read/write each other's
  # output without umask gymnastics.
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

  systemd.tmpfiles.rules =
    let
      streaming = config.nori.fs.streaming.path;
      library = config.nori.fs.library.path;
    in
    [
      # @streaming — re-derivable tier, *arr libraries + download staging.
      # qBittorrent INCOMPLETE lives off-subvol (NVMe StateDirectory) —
      # see qbittorrent.nix.
      "d ${streaming}                     02775 root media -"
      "d ${streaming}/movies              02775 root media -"
      "d ${streaming}/shows               02775 root media -"
      "d ${streaming}/music               02775 root media -"
      "d ${streaming}/.downloads          02775 root media -"
      "d ${streaming}/.downloads/complete 02775 root media -"
      # @library — curated tier, hand-uploaded media
      "d ${library}                         02775 root media -"
      "d ${library}/books                   02775 root media -"
      "d ${library}/comics                  02775 root media -"
    ];
}
