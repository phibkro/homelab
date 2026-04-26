{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Komga — comics/manga server. Scans a directory tree for CBZ/CBR/
  # PDF/EPUB files, exposes them via web UI + native apps (Tachiyomi
  # extension, Paperback, Komelia) + OPDS feed for e-readers.
  #
  # Library lives at /mnt/media/library/comics on @library — the
  # curated tier (daily snapshot + restic). Komga doesn't auto-grab;
  # files are hand-uploaded or synced in by other means.
  #
  # Default port 8080 collides with Open WebUI. Remapped to 8085 via
  # the settings.server.port submodule.
  #
  # First-run setup:
  #   1. Visit https://comics.nori.lan
  #   2. Create the first user (becomes admin) on the registration form
  #   3. Libraries → Add Library →
  #        Name: Comics
  #        Root folder: /mnt/media/library/comics
  #        scan: deep (full scan on first add)
  #   4. (optional) OPDS is at /api/v1/opds/v2; point e-reader apps
  #      at that path with HTTP Basic auth (username/password set above).
  services.komga = {
    enable = true;
    user = "komga";
    group = "komga";
    openFirewall = false;
    settings.server.port = 8085;
  };

  users.users.komga.extraGroups = [ "media" ];

  systemd.services.komga.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
    BindPaths = [ "/mnt/media/library" ];
  };

  nori.lanRoutes.comics = {
    port = 8085;
    monitor = { };
  };
}
