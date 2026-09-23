{
  config,
  lib,
  ...
}:

lib.mkIf ((config.nori.fs ? downloads) && (config.nori.fs ? library)) {
  /*
    Cross-cutting shared resources for the *arr stack — the `media`
    group + the shared library/download tmpfiles.

    Gated on `nori.fs.{downloads,library}` being declared, so hosts
    without these datasets do not get tmpfiles for absent paths.
    Workstation declares both via disko-media.nix.

    Why a dedicated `media` group: each service keeps its own UID, but
    shared group access lets the acquisition services read and write the
    same trees. Sonarr and Radarr import into @downloads, so they can
    hardlink qBittorrent completions. Lidarr imports into @library/music;
    Btrfs cannot hardlink across that subvolume boundary. Setgid (02775)
    propagates the media group without per-service ownership rewrites.

    qBittorrent's INCOMPLETE dir is deliberately off-subvolume for NVMe
    IO isolation; see qbittorrent.nix.
  */

  users.groups.media = { };

  /*
    Jellyfin joins `media` here (not in its own module) so jellyfin.nix
    stays unaware of the *arr stack — the *arrs are the ones adding the
    group; jellyfin is just a downstream consumer of what they produce.
  */
  users.users.jellyfin = lib.mkIf config.services.jellyfin.enable {
    extraGroups = [ "media" ];
  };

  systemd.tmpfiles.rules =
    let
      downloads = config.nori.fs.downloads.path;
      library = config.nori.fs.library.path;
      musicPath = "${library}/${config.nori.inventory.datasets.music.storage.relativePath}";
    in
    [
      "d ${downloads}                     02775 root media -"
      "d ${downloads}/movies              02775 root media -"
      "d ${downloads}/shows               02775 root media -"
      "d ${downloads}/music               02775 root media -"
      "d ${downloads}/.downloads          02775 root media -"
      "d ${downloads}/.downloads/complete 02775 root media -"
      "d ${library}                         02775 root media -"
      "d ${library}/books                   02775 root media -"
      "d ${library}/comics                  02775 root media -"
      "d ${musicPath}                        02775 root media -"
    ];
}
