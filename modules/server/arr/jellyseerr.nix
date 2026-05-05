{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Jellyseerr — request UI for users. Family members log in (with their
  # Jellyfin account, post-OIDC), search for a movie/show, click "Request",
  # and Jellyseerr forwards the request to Sonarr/Radarr to grab. Removes
  # the "ask Philip via SMS to add this show" loop.
  #
  # First-run setup:
  #   1. Visit https://requests.nori.lan
  #   2. First-time wizard: set up sign-in method
  #        Option A — Jellyfin: tie to the existing Jellyfin auth so users
  #          who already have a Jellyfin account just sign in. Recommended
  #          (single source of family identity).
  #        Option B — local accounts: Jellyseerr-only credentials.
  #   3. Add Sonarr → URL http://localhost:8989, paste API key, default
  #      quality profile, root folder /mnt/media/streaming/shows
  #   4. Add Radarr similarly with /mnt/media/streaming/movies
  #   5. (Optional) Settings → Notifications → ntfy webhook for new
  #      requests / approvals.
  #
  # Jellyseerr doesn't touch /mnt/media — it's API-orchestration only,
  # so it doesn't join the `media` group.
  services.seerr = {
    enable = true;
    openFirewall = false;
    port = 5055;
  };

  nori.harden.seerr = { };

  nori.lanRoutes.requests = {
    port = 5055;
    monitor = { };
  };

  # Pattern A — request history + Jellyfin auth links. DynamicUser
  # → /var/lib/jellyseerr is a symlink to /var/lib/private/jellyseerr;
  # restic stores symlinks as symlinks, so we point at the target.
  nori.backups.jellyseerr.paths = [ "/var/lib/private/jellyseerr" ];
}
