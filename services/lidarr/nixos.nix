{ config, lib, ... }:
let
  musicDataset = config.nori.inventory.datasets.music;
  musicPath = "${config.nori.fs.library.path}/${musicDataset.storage.relativePath}";
in
lib.mkIf (lib.elem "lidarr" config.nori.inventory.currentWorkloads) {
  /*
    Lidarr — music management. It watches Prowlarr for releases, sends grabs
    to qBittorrent, and imports finished tracks into the music library.
    The library is under @library while qBittorrent completions are under
    @downloads. Btrfs cannot hardlink across this boundary; do not assume
    the import preserves the seeding inode. The music path is
    `${nori.fs.library.path}/music`. Navidrome and Jellyfin read the same
    local library.

    First-run setup:
      1. Visit https://music.${nori.domain}
      2. Set admin password
      3. Settings → Media Management → Root Folders →
           /mnt/media/library/music
      3a. Settings → Media Management → "Importing" →
            "Minimum Free Space When Importing" → 5 GB.
            See sonarr.nix for the rationale + qbittorrent.nix for the
            wedge this prevents.
      4. Settings → Download Clients → Add → qBittorrent
           Host: localhost  Port: 8083
           Username/Password: from qBittorrent
           Category: music-lidarr
      5. Copy Lidarr's API key from Settings → General → API Key.
         In Prowlarr (indexers.home.phibkro.org) → Settings → Apps → Add →
         Lidarr.
      6. Add Artists / Albums via the UI.
  */
  services.lidarr = {
    enable = true;
    user = "lidarr";
    group = "lidarr";
    openFirewall = false;
  };

  # See sonarr.nix for the env-var override + auth-disabled rationale.
  systemd.services.lidarr.environment = {
    LIDARR__AUTH__METHOD = "Forms";
    LIDARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
  };

  users.users.lidarr.extraGroups = [ "media" ];

  nori.harden.lidarr.binds = [
    config.nori.fs.downloads.path
    musicPath
  ];

  nori.backups.lidarr.include = [ "/var/lib/lidarr" ];
}
