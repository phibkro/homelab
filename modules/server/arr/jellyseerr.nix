{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Jellyseerr — request UI for users. Family members log in (via
  # Authelia OIDC, see below), search for a movie/show, click "Request",
  # and Jellyseerr forwards the request to Sonarr/Radarr to grab.
  # Removes the "ask Philip via SMS to add this show" loop.
  #
  # First-run setup:
  #   1. just oidc-key requests
  #      → outputs raw + PBKDF2 hash; copy both
  #   2. sops secrets/secrets.yaml → paste:
  #        oidc-requests-client-secret: '<raw>'
  #        oidc-requests-client-secret-hash: '<hash>'
  #   3. just rebuild
  #   4. Visit https://requests.nori.lan
  #   5. First-time wizard: set up sign-in method
  #        Pick "Local accounts" or "Jellyfin" — either works alongside
  #        OIDC. Create a master admin first (recovery path if Authelia
  #        is ever down).
  #   6. Settings → General → OpenID Connect:
  #        Issuer URL:   https://auth.nori.lan
  #        Client ID:    requests
  #        Client Secret: paste raw secret from
  #                       /run/secrets/oidc-requests-client-secret
  #                       (cat it on the host)
  #        Scopes:       openid email profile
  #        Save. The redirect URI in Authelia (auto-set by lan-route) is
  #        https://requests.nori.lan/login/oidc-callback — must match
  #        whatever Jellyseerr actually uses; tweak the lanRoute
  #        `oidc.redirectPath` below if Jellyseerr's docs say otherwise.
  #   7. Add Sonarr → URL http://localhost:8989, paste API key, default
  #      quality profile, root folder /mnt/media/streaming/shows
  #   8. Add Radarr similarly with /mnt/media/streaming/movies
  #   9. (Optional) Settings → Notifications → ntfy webhook for new
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

  # Web-UI-managed OIDC (like Beszel/PocketBase) — the `oidc` block
  # generates the Authelia client + sops secret + env-file template;
  # the operator pastes the raw secret + redirect URI into Jellyseerr's
  # admin UI on first run (see header comment). EnvironmentFile is NOT
  # wired because Jellyseerr doesn't accept OIDC config via env vars.
  nori.lanRoutes.requests = {
    port = 5055;
    monitor = { };
    audience = "family";
    oidc = {
      clientName = "Jellyseerr";
      redirectPath = "/login/oidc-callback";
    };
    dashboard = {
      title = "Jellyseerr";
      icon = "sh:jellyseerr";
      group = "Acquire";
      description = "Request shows / movies (family-facing)";
    };
  };

  # Pattern A — request history + Jellyfin auth links. DynamicUser
  # → /var/lib/jellyseerr is a symlink to /var/lib/private/jellyseerr;
  # restic stores symlinks as symlinks, so we point at the target.
  nori.backups.jellyseerr.paths = [ "/var/lib/private/jellyseerr" ];
}
