{
  config,
  lib,
  ...
}:

lib.mkMerge [
  {
    nori.services.paperless.tags = [
      "family-tier"
      "media-reader"
      "stateful"
    ];

    /*
      Paperless web UI. audience=operator: it's the operator's research
      archive, tailnet auth suffices (no per-user identity, so no OIDC).
      The UI is mobile-responsive + has first-party iOS/Android apps —
      pointing them at https://papers.nori.lan over the tailnet IS the
      phone-access path (no separate Syncthing export needed; the OCR'd
      full-text search lives server-side anyway).
    */
    nori.lanRoutes.papers = {
      port = 28981; # paperless default; no collision (see `just list-ports`)
      runsOn = "aurora";
      exposeOnTailnet = true;
      monitor = { };
      dashboard = {
        title = "Paperless";
        icon = "si:paperlessngx";
        group = "Consume";
        description = "Document archive — OCR + full-text search";
      };
    };
  }
  (lib.mkIf config.nori.services.paperless.enabled {
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

      Database: createLocally=true joins aurora's shared
      services.postgresql instance (already on via immich) — same idiom
      as miniflux. Postgres (not the default SQLite) because the
      full-text index + metadata want a real RDBMS at archive scale.

      First-run setup:
        1. Visit https://papers.nori.lan
        2. paperless-manage createsuperuser  (on aurora, as the
           paperless user) — or set settings.PAPERLESS_ADMIN_USER +
           a passwordFile. No superuser is auto-created without one.
        3. Log in → the consume dir (/var/lib/paperless/consume) is
           watched; anything dropped there is OCR'd + indexed.
        4. On phone: install the Paperless mobile app, point at
           https://papers.${config.nori.domain} over the tailnet, log in.
    */
    services.paperless = {
      enable = true;
      user = "paperless";
      address = "0.0.0.0"; # Caddy on pi proxies in over the tailnet
      port = 28981;

      database.createLocally = true; # joins aurora's shared postgres

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
        # Primary host: the Caddy-on-pi proxied domain. Also accept aurora's
        # own tailnet IP for DIRECT operator access when the pi entry plane is
        # down or rebuilding — audience=operator means the tailnet IS the trust
        # perimeter, so reaching the backend directly over the tailnet carries
        # the same posture as the proxied route (just without Caddy's TLS).
        PAPERLESS_ALLOWED_HOSTS = "papers.${config.nori.domain},${config.nori.hosts.aurora.tailnetIp}";
        PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://papers.${config.nori.domain},http://${config.nori.hosts.aurora.tailnetIp}:28981";
      };
    };

    # `media` group for write access to @library (shared with komga +
    # calibre-web); lets paperless write mediaDir under the 02775
    # root:media library subvol.
    users.users.paperless.extraGroups = [ "media" ];

    # Admin password, sops-decrypted from the default secrets file
    # (secrets/secrets.yaml — aurora is already a recipient). Add the
    # `paperless-admin-password` key there before the next aurora deploy:
    #   sops secrets/secrets.yaml   →   paperless-admin-password: <your-pw>
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
  })
]
