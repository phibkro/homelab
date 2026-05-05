{
  config,
  lib,
  pkgs,
  ...
}:

{
  # calibre-web — web UI for an ebook library. Distinct from Calibre's
  # own content server: calibre-web is community-maintained, has a
  # nicer UI, supports OPDS at /opds (e-readers, mobile apps), and
  # does on-the-fly format conversion for Kindle/Kobo when the
  # `calibre` binary is available on PATH.
  #
  # Library lives at /mnt/media/library/books on @library — the
  # curated tier (daily snapshot + restic). Books are typically
  # hand-uploaded via the web UI (no Readarr in scope; auto-grabbing
  # books was deferred).
  #
  # Default port 8083 collides with qBittorrent (which itself remapped
  # off the 8080 collision with Open WebUI) — calibre-web → 8084.
  #
  # First-run setup:
  #   1. Visit https://books.nori.lan
  #   2. Default admin login: admin / admin123
  #   3. Admin → Edit Basic Configuration → Calibre Database Directory
  #        /mnt/media/library/books
  #   4. Admin → Users → admin → Change Password
  #   5. (optional) OPDS is at /opds; provide that URL to e-reader
  #      apps (KOReader, Moon+ Reader, Marvin, etc.) for syncing.
  # Workaround for a current-nixpkgs build failure: calibre-web's
  # upstream pin says `requests<2.33.0` but nixpkgs ships requests
  # 2.33.1. The pin is overly strict (the breaking change in 2.33.1 is
  # a deprecated-API removal that calibre-web doesn't use). Relax via
  # pythonRelaxDeps. Drop this override when nixpkgs ships calibre-web
  # 0.6.28+ (which broadens the pin) or pins requests 2.32.x downstream.
  nixpkgs.overlays = [
    (_final: prev: {
      calibre-web = prev.calibre-web.overridePythonAttrs (old: {
        pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "requests" ];
      });
    })
  ];

  services.calibre-web = {
    enable = true;
    user = "calibre-web";
    group = "calibre-web";
    listen = {
      ip = "127.0.0.1";
      port = 8084;
    };
    openFirewall = false;
    options = {
      calibreLibrary = "${config.nori.fs.library.path}/books";
      enableBookUploading = true; # admin upload via web UI
      enableBookConversion = true; # send-to-kindle/kobo conversion
    };
  };

  # Member of `media` group so calibre-web can write into @library
  # alongside Komga (and any other future curated-media service).
  users.users.calibre-web.extraGroups = [ "media" ];

  # Bootstrap: calibre-web fails to start if its library dir lacks
  # `metadata.db`. Initialize an empty Calibre library on first run if
  # one isn't there yet.
  systemd.services.calibre-web.preStart =
    let
      bookDir = "${config.nori.fs.library.path}/books";
    in
    lib.mkBefore ''
      if [ ! -f ${bookDir}/metadata.db ]; then
        mkdir -p ${bookDir}
        ${pkgs.calibre}/bin/calibredb \
          --library-path ${bookDir} \
          list >/dev/null 2>&1 || true
      fi
    '';

  nori.harden.calibre-web.binds = [ config.nori.fs.library.path ];

  nori.lanRoutes.books = {
    port = 8084;
    monitor = { };
    audience = "family";
    # Forward-auth via Authelia. /opds/* + /kobo/* exempt so KOReader,
    # Moon+ Reader, Marvin, and Kobo Sync clients can hit the OPDS
    # catalog with HTTP Basic auth (calibre-web's own user) — they
    # don't follow OAuth redirects. /api/* exempt for completeness.
    # Browser users go through Authelia.
    forwardAuth.exemptPaths = [
      "/opds/*"
      "/kobo/*"
      "/api/*"
    ];
    dashboard = {
      title = "calibre-web";
      icon = "sh:calibre-web";
      group = "Consume";
      description = "Ebook reader + OPDS";
    };
  };

  # Pattern A — calibre-web's user/session DB. The book library
  # itself lives at /mnt/media/library/books (already in
  # media-irreplaceable). Static `calibre-web` user.
  nori.backups.calibre-web.paths = [ "/var/lib/calibre-web" ];
}
