{
  config,
  lib,
  ...
}:

lib.mkIf ((config.nori.fs ? downloads) && (config.nori.fs ? library)) {
  # Cross-cutting shared resources for the *arr stack — the `media`
  # group + the shared library/download tmpfiles.
  #
  # Gated on `nori.fs.{downloads,library}` being declared, so hosts
  # that import the services bundle for its route declarations only
  # (pi, aurora) don't pull in tmpfiles for paths that don't exist.
  # Workstation declares both via disko-media.nix.
  #
  # Why a dedicated `media` group: qBittorrent → *arr import is a
  # hardlink (saves disk + atomic move), and btrfs hardlinks don't
  # cross subvolumes — so all *arr libraries + the qBittorrent complete
  # dir share @downloads, and every consumer joins `media` via its own
  # module. Setgid (02775) on the dirs propagates the group to new
  # files without per-service umask config.
  #
  # qBittorrent's INCOMPLETE dir is deliberately off-subvol — NVMe IO
  # isolation; see qbittorrent.nix.

  users.groups.media = { };

  # Jellyfin joins `media` here (not in its own module) so jellyfin.nix
  # stays unaware of the *arr stack — the *arrs are the ones adding the
  # group; jellyfin is just a downstream consumer of what they produce.
  users.users.jellyfin = lib.mkIf config.services.jellyfin.enable {
    extraGroups = [ "media" ];
  };

  systemd.tmpfiles.rules =
    let
      downloads = config.nori.fs.downloads.path;
      library = config.nori.fs.library.path;
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
      "d ${library}/music                   02775 root media -"
    ];
}
