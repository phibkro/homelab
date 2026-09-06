_:

{
  /*
    Seerr — request UI for users. Family members log in with the same
    Jellyfin account they use for playback, search for a movie/show,
    click "Request", and Seerr forwards the request to Sonarr/Radarr.
    Removes the "ask Philip via SMS to add this show" loop.

    First-run setup:
      1. Visit https://requests.home.phibkro.org and choose Jellyfin
         during the setup wizard. Use the dedicated Jellyfin admin as
         Seerr's owner/recovery account.
      2. Set Jellyfin internal URL to http://localhost:8096 and external
         URL to https://media.home.phibkro.org.
      3. Settings → Users: import the explicitly approved family Jellyfin
         users. Give defaults request-only permissions, no management
         permissions, and configure request quotas/manual approval.
      4. Create one local owner/recovery account with a unique password.
         Keep "new Jellyfin sign-in" disabled so membership requires an
         explicit import rather than merely possessing a Jellyfin account.
      5. Add Sonarr → URL http://localhost:8989, paste API key, default
         quality profile, root folder /mnt/media/downloads/shows
      6. Add Radarr similarly with /mnt/media/downloads/movies
      7. (Optional) Settings → Notifications → ntfy webhook for new
         requests / approvals.

    Jellyseerr doesn't touch /mnt/media — it's API-orchestration only,
    so it doesn't join the `media` group.
  */
  services.seerr = {
    enable = true;
    openFirewall = false;
    port = 5055;
  };

  nori.harden.seerr = { };

  # DynamicUser — /var/lib/jellyseerr is a symlink; restic stores the
  # link not the target, so back up the real path.
  nori.backups.jellyseerr.include = [ "/var/lib/private/jellyseerr" ];
}
