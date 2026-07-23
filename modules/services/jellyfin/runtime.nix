{ config, ... }:

/**
  Host-local Jellyfin realization.

  Imported only on the placement host selected by the pure inventory. Global
  endpoint, audience, dashboard, and placement metadata live in manifest.nix.
*/
{
  /*
    Jellyfin — media streaming server. Library paths configured via
    web UI (Dashboard → Libraries → Add).

    First-time setup: connect to
      http://workstation.saola-matrix.ts.net:8096
    …walk through the wizard. Admin user is independent of the
    system `nori` user.

    Internet-facing account posture:
      * one non-admin user per family member; never share the admin login
      * unique passwords stored in the family password manager
      * configure a failed-login lockout threshold in each user policy
      * disable accounts promptly when access is revoked

    NVENC on the RTX 5060 Ti works but requires opt-in via the web
    UI (Dashboard → Playback → Transcoding) — Jellyfin stores it
    in /var/lib/jellyfin/config/encoding.xml, not a Nix option. The
    host-wide nvidia driver exposes the GPU automatically.

    Intended UI state — reapply if encoding.xml ever gets stomped:
      Hardware acceleration: Nvidia NVENC
      Decoding ticked:    H264, HEVC, MPEG2, MPEG4, VC1, VP9, AV1,
                          HEVC 10bit, VP9 10bit
      Decoding unticked:  VP8 (no real content), HEVC RExt 8/10/12bit
                          (pro/medical, won't be in library)
      Enhanced NVDEC decoder: on
      Hardware encoding: on
      Encoding formats allowed: HEVC + AV1 (H264 always-on by default)
      Tone mapping: off (only matters for HDR→SDR on non-HDR clients)
  */

  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  # /mnt/media/* is owned nori:users — group membership grants read.
  users.users.jellyfin.extraGroups = [ "users" ];

  /*
    Tighten Jellyfin's mount namespace beyond the upstream module's
    default hardening. Without this, the in-app folder picker can
    browse the entire host filesystem (read-only, but still leaky).

    Strategy: tmpfs over /mnt and /srv, then bind-mount only the
    specific paths Jellyfin should see back in (read-only — Jellyfin
    never writes to /mnt/media). ProtectHome=mkForce true also hides
    /home and /root (the upstream module doesn't set this).

    The /mnt/media parent is bound rather than enumerating per-subvol
    because Jellyfin's library config in the web UI references paths
    under /mnt/media/{streaming,home-videos,...} — needs the parent
    visible so the in-app folder picker walks the tree. Adding a new
    media subvolume in nori.fs becomes available to Jellyfin
    automatically, no harden update.
  */
  nori.harden.jellyfin.readOnlyBinds = [
    "/mnt/media"
    config.nori.fs.share.path
  ];

  /*
    Pattern A — library scan, watch progress, user accounts. The
    library can be re-derived from media files on disk, but watch
    history is irreplaceable convenience data. Largest of the
    service-state repos at ~210MB.
  */
  nori.backups.jellyfin.include = [ "/var/lib/jellyfin" ];
}
