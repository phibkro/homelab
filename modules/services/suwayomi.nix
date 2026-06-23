{
  config,
  lib,
  ...
}:

lib.mkMerge [
  {
    nori.services.suwayomi.tags = [
      "family-tier"
      "media-server"
      "stateful"
    ];

    nori.lanRoutes.manga = {
      port = 8088;
      runsOn = "aurora";
      exposeOnTailnet = true; # pi's Caddy proxies cross-host over tailnet
      monitor = { };
      audience = "family";
      /*
        Forward-auth via Authelia. /api/* exempt so the Tachiyomi/Mihon
        app and OPDS readers reach Suwayomi's GraphQL + OPDS endpoints
        with their own auth, the same exemption komga.nix carries for
        the OPDS catalog.
      */
      forwardAuth.exemptPaths = [ "/api/*" ];
      dashboard = {
        title = "Suwayomi";
        icon = "sh:suwayomi";
        group = "Acquire";
        description = "Manga downloader (Tachiyomi sources)";
      };
    };
  }
  (lib.mkIf config.nori.services.suwayomi.enabled {
    /*
      Suwayomi-Server — manga acquisition. Runs Tachiyomi/Mihon source
      extensions, browses + downloads chapters as CBZ. Self-contained:
      it has its own extension-based sources, so unlike the *arr stack
      it does NOT use Prowlarr or qBittorrent.

      ── Placement: aurora, co-located with komga ───────────────────────
      Suwayomi's output IS komga's input. komga reads its own host's
      `nori.fs.library`; on aurora that's /mnt/family/library. Writing
      downloads straight there means komga indexes them with zero
      cross-host replication — the workstation→aurora library bridge
      (nori.replicas, btrfs send/receive) is unbuilt (P15). Co-locating
      with the consumer sidesteps it. This is NOT a violation of the
      "acquisition lives on workstation" topology line — that line is
      about the GPU + Prowlarr/qBittorrent *arr cluster, which Suwayomi
      isn't part of.

      ── State vs downloads (tier separation) ───────────────────────────
      State (sqlite, extensions, server.conf) stays at the default
      /var/lib/suwayomi-server (StateDirectory on aurora's root) — it's
      service-tier, re-buildable. Only the CBZ DOWNLOADS go to the
      curated library at /mnt/family/library/manga (irreplaceable tier,
      already restic-backed via nori.fs.library), set via
      `settings.server.downloadsPath`. Keeping them apart stops service
      churn polluting the irreplaceable library subvol.

      ── First-run setup ────────────────────────────────────────────────
        1. Visit https://manga.${nori.domain}
        2. Settings → Browse → Extension repos → add a Tachiyomi/Mihon
           extension repo (e.g. the Keiyoushi index), then install the
           source extensions you want.
        3. Settings → Downloads → confirm "Download as CBZ" is on (set
           declaratively below) and downloads land in the library.
        4. Browse a source → add manga to library → download chapters.
           They land at /mnt/family/library/manga/<source>/<manga>/.
        5. In komga (https://comics.${nori.domain}) add a second library:
             Name: Manga
             Root folder: /mnt/family/library/manga
           komga indexes the CBZ tree alongside the existing comics one.
    */
    services.suwayomi-server = {
      enable = true;
      user = "suwayomi";
      group = "suwayomi";
      openFirewall = false;
      settings.server = {
        ip = "0.0.0.0";
        port = 8088;
        downloadAsCbz = true;
        downloadsPath = "${config.nori.fs.library.path}/manga";
      };
    };

    # Write to the curated library tree alongside calibre/komga/navidrome.
    users.users.suwayomi.extraGroups = [ "media" ];

    nori.harden.suwayomi-server.binds = [ "${config.nori.fs.library.path}/manga" ];

    /*
      Pattern A — Suwayomi's library/source/read-progress sqlite at
      /var/lib/suwayomi-server. Static `suwayomi` user (not DynamicUser).
      The downloaded CBZ tree lives at /mnt/family/library/manga, already
      covered by the irreplaceable library backup, so it's excluded here.
    */
    nori.backups.suwayomi.include = [ "/var/lib/suwayomi-server" ];
  })
]
