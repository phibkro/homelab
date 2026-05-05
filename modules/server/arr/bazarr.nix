{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Bazarr — subtitle automation. Reads Sonarr's + Radarr's libraries,
  # finds missing subtitles per the user's language preferences, fetches
  # them from configured providers (OpenSubtitles, Subscene, etc.) and
  # writes the .srt/.ass files alongside the video files.
  #
  # First-run setup:
  #   1. Visit https://subtitles.nori.lan
  #   2. Set admin password
  #   3. Settings → Languages → enabled languages (Norwegian + English
  #      most common)
  #   4. Settings → Providers → enable OpenSubtitles (free, generous
  #      quota; requires a free account); add others as desired
  #   5. Settings → Sonarr → Host: localhost, Port: 8989, paste API key
  #      Settings → Radarr → Host: localhost, Port: 7878, paste API key
  #   6. Bazarr scans on a schedule + on-demand; new subtitles land
  #      next to the video file automatically.
  services.bazarr = {
    enable = true;
    user = "bazarr";
    group = "bazarr";
    openFirewall = false;
    listenPort = 6767;
  };

  # Bazarr writes subtitle files into Sonarr's + Radarr's library
  # paths. Same `media` group membership as the other servarrs.
  users.users.bazarr.extraGroups = [ "media" ];

  nori.harden.bazarr.binds = [ config.nori.fs.streaming.path ];

  nori.lanRoutes.subtitles = {
    port = 6767;
    monitor = { };
  };

  # Pattern A — Bazarr's config + provider history. Static `bazarr` user.
  nori.backups.bazarr.paths = [ "/var/lib/bazarr" ];
}
