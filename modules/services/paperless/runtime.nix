{
  config,
  ...
}:
let
  selfTailnetIp = config.nori.hosts.${config.networking.hostName}.tailnetIp;
in
{
  /*
    Paperless-ngx — document archive. Drop a PDF in the consume dir →
    OCR + full-text index + tag + serve. The sink for the papers
    acquisition pipeline (docs/specs/2026-06-23-papers-acquisition.md):
    the OA fetcher resolves a DOI/arXiv-id → downloads the PDF →
    drops it in the consume dir, Paperless does the rest.

    Storage split (mirrors calibre-web + komga on @library):
      - originals + archive PDFs + thumbnails → mediaDir on
        /mnt/family/library/papers (irreplaceable tier: snapshotted +
        restic'd as part of media-irreplaceable). The originals are
        the irreplaceable artifact; they belong on the vault subvol,
        not root NVMe.
      - DB / search index / consume dir → /var/lib/paperless (service
        tier). The DB holds user-entered tags + correspondents that
        don't rebuild from originals → logical pg_dump before restic
        (Pattern C1 below).

    Database: createLocally=true joins the converged host's shared
    services.postgresql instance (already enabled by Immich). Postgres
    remains preferable to SQLite for the full-text index and metadata.

    First-run setup:
      1. Visit https://papers.home.phibkro.org
      2. `paperless-manage createsuperuser` as the paperless user, or use
         the declarative admin settings below.
      3. Log in → the consume dir (/var/lib/paperless/consume) is
         watched; anything dropped there is OCR'd + indexed.
      4. On phone: install the Paperless mobile app, point at
         https://papers.${config.nori.domain} over the tailnet, log in.
  */
  services.paperless = {
    enable = true;
    user = "paperless";
    address = "0.0.0.0"; # Caddy is co-located; tailnet direct access remains available
    port = 28981;

    database.createLocally = true;

    # Originals + archive land on the irreplaceable vault subvol.
    mediaDir = "${config.nori.fs.library.path}/papers";

    # Declarative superuser: the module creates/updates `PAPERLESS_ADMIN_USER`
    # with the password from this sops-decrypted file on each start (idempotent
    # — only re-applies when the user:password state changes). Makes the login
    # reproducible on a fresh DB instead of a manual `createsuperuser`. The
    # password is the single source of truth here: deploying RESETS nori's
    # password to whatever the sops secret holds.
    passwordFile = config.sops.secrets.paperless-admin-password.path;

    settings = {
      PAPERLESS_OCR_LANGUAGE = "eng"; # academic papers; add "+nor" if needed
      PAPERLESS_ADMIN_USER = "nori"; # matches the existing superuser
      PAPERLESS_URL = "https://papers.${config.nori.domain}";
      # Accept the public Caddy route and the converged host's direct tailnet
      # endpoint for operator recovery.
      PAPERLESS_ALLOWED_HOSTS = "papers.${config.nori.domain},${selfTailnetIp}";
      PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://papers.${config.nori.domain},http://${selfTailnetIp}:28981";
    };
  };

  # `media` group for write access to @library (shared with komga +
  # calibre-web); lets paperless write mediaDir under the 02775
  # root:media library subvol.
  users.users.paperless.extraGroups = [ "media" ];

  # Admin password, sops-decrypted from the default secrets file.
  sops.secrets.paperless-admin-password = {
    owner = "paperless";
    mode = "0400";
  };

  /*
    FS hardening — one entry per systemd unit (paperless is multi-unit:
    web, consumer, task-queue, scheduler). Each unit needs the library
    path bound writable through the /mnt:ro tmpfs overlay: the consumer
    + task-queue write originals/archive to mediaDir, web + scheduler
    share the namespace via JoinsNamespaceOf/bindsTo so they see the
    same mount. The upstream module already lists mediaDir in
    ReadWritePaths (needed under its ProtectSystem=strict); `binds`
    makes the real dir visible through harden's tmpfs overlay.

    (Spelled out per-unit rather than via genAttrs because the
    every-service-has-fs-hardening guard greps for the literal
    `nori.harden.<name>` substring.)
  */
  nori.harden.paperless-web.binds = [ config.nori.fs.library.path ];
  nori.harden.paperless-consumer.binds = [ config.nori.fs.library.path ];
  nori.harden.paperless-task-queue.binds = [ config.nori.fs.library.path ];
  nori.harden.paperless-scheduler.binds = [ config.nori.fs.library.path ];

  /*
    Pattern C1 — pg_dump to /var/backup/postgresql/, restic picks it
    up. The originals at /mnt/family/library/papers are already in
    media-irreplaceable; only the DB needs an explicit dump (Paperless
    stores tags/correspondents/index there, not derivable from the
    PDFs). services.postgresqlBackup is idempotent — appends to the
    shared `databases` list alongside miniflux.
  */
  services.postgresqlBackup = {
    enable = true;
    databases = [ "paperless" ];
    startAt = "*-*-* 03:30:00"; # before restic-backups-paperless at 04:30
    pgdumpOptions = "--no-owner";
  };

  nori.backups.paperless = {
    include = [ "/var/backup/postgresql/paperless.sql.gz" ];
    tier = "irreplaceable";
    timer = "*-*-* 04:30:00";
  };
}
