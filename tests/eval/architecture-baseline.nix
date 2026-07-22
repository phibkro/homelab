{
  inputs,
  lib,
  ...
}:

/**
  Behavior baseline for the concern-oriented architecture migration.

  This test deliberately describes behavior, not implementation paths. The
  expected projection pins resolved inventory placement after retirement of
  the legacy service activation registry.

  The route fingerprint covers the cross-host fields most likely to drift when
  catalog declarations move out of runtime modules. Rich adapter behavior is
  covered independently by the route, DNS, Gatus, and multi-host tests.
*/

let
  hosts = inputs.self.nixosConfigurations;
  homes = {
    workstation = hosts.workstation.config.home-manager.users.nori;
    aurora = hosts.aurora.config.home-manager.users.nori;
    pi = hosts.pi.config.home-manager.users.nori;
    pavilion = hosts.pavilion.config.home-manager.users.nori;
    macbook = inputs.self.homeConfigurations.macbook.config;
  };

  hasHomePackage =
    homeName: packageName:
    lib.any (package: lib.getName package == packageName) homes.${homeName}.home.packages;

  actualWorkloads = lib.mapAttrs (_: host: host.config.nori.inventory.currentWorkloads) hosts;

  expectedWorkloads = {
    workstation = [
      "bazarr"
      "beszel-agent"
      "blocky"
      "btrbk-replica-target"
      "clamor"
      "disk-alert"
      "gatus"
      "jellyfin"
      "jellyseerr"
      "lidarr"
      "music-ingest"
      "node-exporter"
      "ntfy-notify"
      "nvidia-gpu-exporter"
      "ollama"
      "open-webui"
      "prowlarr"
      "qbittorrent"
      "radarr"
      "recyclarr"
      "samba"
      "sonarr"
      "stremio"
      "syncthing"
    ];
    aurora = [
      "beszel-agent"
      "btrbk-replication"
      "calibre-web"
      "filmder"
      "glance"
      "grafana"
      "heim"
      "immich"
      "komga"
      "miniflux"
      "navidrome"
      "node-exporter"
      "ntfy-notify"
      "nvidia-gpu-exporter"
      "paperless"
      "radicale"
      "restic-target"
      "samba"
      "suwayomi"
      "syncthing"
      "vaultwarden"
    ];
    pi = [
      "authelia"
      "beszel-agent"
      "beszel-hub"
      "blocky"
      "caddy"
      "gatus"
      "heartbeat"
      "ntfy-notify"
      "ntfy-server"
      "victorialogs-server"
      "victoriametrics"
    ];
    pavilion = [
      "beszel-agent"
      "node-exporter"
    ];
  };

  authMode =
    route:
    if route.oidc != null then
      "oidc"
    else if route.forwardAuth != null then
      "forward-auth"
    else if route.noAuthReason != null then
      "exception"
    else
      "none";

  routeFingerprint = route: {
    inherit (route)
      port
      runsOn
      audience
      exposeOnTailnet
      ;
    auth = authMode route;
    monitored = route.monitor != null;
    dashboard = route.dashboard != null;
  };

  actualRoutes = lib.mapAttrs (_: routeFingerprint) hosts.pi.config.nori.lanRoutes;

  migratedRuntimePlacements = {
    authelia = [ "pi" ];
    bazarr = [ "workstation" ];
    beszel-agent = [
      "workstation"
      "aurora"
      "pi"
      "pavilion"
    ];
    beszel-hub = [ "pi" ];
    blocky = [
      "workstation"
      "pi"
    ];
    btrbk-replica-target = [ "workstation" ];
    btrbk-replication = [ "aurora" ];
    caddy = [ "pi" ];
    calibre-web = [ "aurora" ];
    disk-alert = [ "workstation" ];
    filmder = [ "aurora" ];
    glance = [ "aurora" ];
    grafana = [ "aurora" ];
    gatus = [
      "workstation"
      "pi"
    ];
    heartbeat = [ "pi" ];
    heim = [ "aurora" ];
    immich = [ "aurora" ];
    jellyfin = [ "workstation" ];
    jellyseerr = [ "workstation" ];
    komga = [ "aurora" ];
    lidarr = [ "workstation" ];
    miniflux = [ "aurora" ];
    music-ingest = [ "workstation" ];
    navidrome = [ "aurora" ];
    node-exporter = [
      "workstation"
      "aurora"
      "pavilion"
    ];
    nvidia-gpu-exporter = [
      "workstation"
      "aurora"
    ];
    ntfy-notify = [
      "workstation"
      "aurora"
      "pi"
    ];
    ntfy-server = [ "pi" ];
    ollama = [ "workstation" ];
    open-webui = [ "workstation" ];
    paperless = [ "aurora" ];
    prowlarr = [ "workstation" ];
    qbittorrent = [ "workstation" ];
    radarr = [ "workstation" ];
    radicale = [ "aurora" ];
    recyclarr = [ "workstation" ];
    restic-target = [ "aurora" ];
    samba = [
      "workstation"
      "aurora"
    ];
    sonarr = [ "workstation" ];
    stremio = [ "workstation" ];
    suwayomi = [ "aurora" ];
    syncthing = [
      "workstation"
      "aurora"
    ];
    vaultwarden = [ "aurora" ];
    victorialogs-server = [ "pi" ];
    victoriametrics = [ "pi" ];
  };

  runtimeEvidenceNames = {
    beszel-hub = "beszel";
    btrbk-replication = "btrbk-family-replica";
    ntfy-notify = "notify";
    ntfy-server = "ntfy";
    victorialogs-server = "victorialogs";
  };
  runtimeEvidenceName = workloadName: runtimeEvidenceNames.${workloadName} or workloadName;
  hasMigratedRuntime =
    workloadName: host: builtins.hasAttr (runtimeEvidenceName workloadName) host.config.nori.backups;
  runtimePlacementCorrect = lib.all (
    workloadName:
    lib.all
      (
        hostName:
        hasMigratedRuntime workloadName hosts.${hostName}
        == lib.elem hostName migratedRuntimePlacements.${workloadName}
      )
      [
        "workstation"
        "aurora"
        "pi"
        "pavilion"
      ]
  ) (lib.attrNames migratedRuntimePlacements);

  migratedCatalogEndpoints = {
    authelia.auth = "pi";
    bazarr.subtitles = "workstation";
    beszel-hub.metrics = "pi";
    ntfy-server.alert = "pi";
    calibre-web.books = "aurora";
    clamor.agents = "workstation";
    filmder.filmder = "aurora";
    glance.home = "aurora";
    grafana.ops = "aurora";
    gatus.uptime = "pi";
    heim.heim = "aurora";
    immich.photos = "aurora";
    jellyfin.media = "workstation";
    jellyseerr.requests = "workstation";
    komga.comics = "aurora";
    lidarr.music = "workstation";
    miniflux.news = "aurora";
    navidrome.audio = "aurora";
    ollama.ai = "workstation";
    paperless.papers = "aurora";
    prowlarr.indexers = "workstation";
    qbittorrent.downloads = "workstation";
    radarr.movies = "workstation";
    radicale.calendar = "aurora";
    sonarr.tv = "workstation";
    stremio.stremio = "workstation";
    suwayomi.manga = "aurora";
    syncthing.sync = "workstation";
    victorialogs-server.logs = "pi";
    victoriametrics.tsdb = "pi";
    vaultwarden.vault = "aurora";
  };
  catalogVisibleEverywhere =
    lib.all
      (
        hostName:
        lib.all (
          workloadName:
          lib.all (
            endpointName:
            hosts.${hostName}.config.nori.inventory.workloads.${workloadName}.endpoints.${endpointName}.runsOn
            == migratedCatalogEndpoints.${workloadName}.${endpointName}
          ) (lib.attrNames migratedCatalogEndpoints.${workloadName})
        ) (lib.attrNames migratedCatalogEndpoints)
      )
      [
        "workstation"
        "aurora"
        "pi"
        "pavilion"
      ];

  lifecycleStateCorrect =
    lib.all
      (
        hostName:
        hosts.${hostName}.config.nori.inventory.workloads.ollama.active
        && !hosts.${hostName}.config.nori.inventory.workloads.open-webui.active
        && hosts.${hostName}.config.nori.inventory.workloads.open-webui.endpoints == { }
      )
      [
        "workstation"
        "aurora"
        "pi"
        "pavilion"
      ];

  papersFetchCompatibility =
    lib.all
      (
        hostName:
        lib.any (
          package: lib.getName package == "papers-fetch"
        ) hosts.${hostName}.config.environment.systemPackages == (hostName == "aurora")
      )
      [
        "workstation"
        "aurora"
        "pi"
        "pavilion"
      ];

  systemProfileRealizationCorrect =
    hosts.workstation.config.programs.hyprland.enable
    && lib.all (hostName: !hosts.${hostName}.config.programs.hyprland.enable) [
      "aurora"
      "pi"
      "pavilion"
    ];

  homeManagerRealizationCorrect =
    lib.all (hostName: hosts.${hostName}.config.home-manager.users.nori.home.stateVersion == "26.05")
      [
        "workstation"
        "aurora"
        "pi"
        "pavilion"
      ];

  homeCapabilityProfilesCorrect =
    lib.all (homeName: hasHomePackage homeName "just" && hasHomePackage homeName "devenv") (
      lib.attrNames homes
    )
    && lib.all (
      homeName:
      hasHomePackage homeName "gh" == lib.elem homeName [
        "workstation"
        "macbook"
      ]
    ) (lib.attrNames homes)
    && lib.all (
      homeName:
      builtins.hasAttr ".claude/settings.json" homes.${homeName}.home.file == lib.elem homeName [
        "workstation"
        "macbook"
      ]
    ) (lib.attrNames homes)
    && homes.workstation.nori.agentNotify.enable
    && !homes.macbook.nori.agentNotify.enable
    && builtins.hasAttr ".codex/AGENTS.md" homes.workstation.home.file
    && lib.all (packageName: hasHomePackage "workstation" packageName) [
      "agent-dispatch"
      "bubblewrap"
      "deno"
    ];

  desktopCapabilityProfilesCorrect =
    lib.all (packageName: hasHomePackage "workstation" packageName) [
      "ghostty"
      "davinci-resolve"
      "audacity"
      "discord"
      "zotero"
    ]
    &&
      lib.all
        (
          homeName:
          lib.all (packageName: !hasHomePackage homeName packageName) [
            "davinci-resolve"
            "audacity"
            "discord"
            "zotero"
          ]
        )
        [
          "aurora"
          "pi"
          "pavilion"
          "macbook"
        ];

  riceInterfaceCorrect =
    hosts.workstation.config.home-manager.users.nori.nori.hyprRice.enable
    && hosts.workstation.config.home-manager.users.nori.wayland.windowManager.hyprland.enable;

  expectedRoutes = {
    agents = {
      port = 4173;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = false;
    };
    ai = {
      port = 11434;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = false;
    };
    alert = {
      port = 8081;
      runsOn = "pi";
      audience = "operator";
      exposeOnTailnet = false;
      auth = "none";
      monitored = true;
      dashboard = false;
    };
    audio = {
      port = 4533;
      runsOn = "aurora";
      audience = "family";
      exposeOnTailnet = true;
      auth = "oidc";
      monitored = true;
      dashboard = true;
    };
    auth = {
      port = 9091;
      runsOn = "pi";
      audience = "public";
      exposeOnTailnet = false;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    books = {
      port = 8084;
      runsOn = "aurora";
      audience = "family";
      exposeOnTailnet = true;
      auth = "forward-auth";
      monitored = true;
      dashboard = true;
    };
    calendar = {
      port = 5232;
      runsOn = "aurora";
      audience = "family";
      exposeOnTailnet = true;
      auth = "exception";
      monitored = true;
      dashboard = true;
    };
    comics = {
      port = 8085;
      runsOn = "aurora";
      audience = "family";
      exposeOnTailnet = true;
      auth = "forward-auth";
      monitored = true;
      dashboard = true;
    };
    downloads = {
      port = 8083;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    filmder = {
      port = 9092;
      runsOn = "aurora";
      audience = "public";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    heim = {
      port = 9094;
      runsOn = "aurora";
      audience = "public";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    home = {
      port = 8086;
      runsOn = "aurora";
      audience = "public";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = false;
    };
    indexers = {
      port = 9696;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    logs = {
      port = 9428;
      runsOn = "pi";
      audience = "operator";
      exposeOnTailnet = false;
      auth = "none";
      monitored = true;
      dashboard = false;
    };
    manga = {
      port = 8088;
      runsOn = "aurora";
      audience = "family";
      exposeOnTailnet = true;
      auth = "forward-auth";
      monitored = true;
      dashboard = true;
    };
    media = {
      port = 8096;
      runsOn = "workstation";
      audience = "family";
      exposeOnTailnet = true;
      auth = "exception";
      monitored = true;
      dashboard = true;
    };
    metrics = {
      port = 8090;
      runsOn = "pi";
      audience = "operator";
      exposeOnTailnet = false;
      auth = "oidc";
      monitored = true;
      dashboard = true;
    };
    movies = {
      port = 7878;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    music = {
      port = 8686;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    news = {
      port = 8087;
      runsOn = "aurora";
      audience = "family";
      exposeOnTailnet = true;
      auth = "oidc";
      monitored = true;
      dashboard = false;
    };
    ops = {
      port = 3000;
      runsOn = "aurora";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    papers = {
      port = 28981;
      runsOn = "aurora";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    photos = {
      port = 2283;
      runsOn = "aurora";
      audience = "family";
      exposeOnTailnet = true;
      auth = "oidc";
      monitored = true;
      dashboard = true;
    };
    requests = {
      port = 5055;
      runsOn = "workstation";
      audience = "family";
      exposeOnTailnet = true;
      auth = "oidc";
      monitored = true;
      dashboard = true;
    };
    uptime = {
      port = 8082;
      runsOn = "pi";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = false;
      dashboard = true;
    };
    stremio = {
      port = 11470;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    subtitles = {
      port = 6767;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    sync = {
      port = 8384;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    tsdb = {
      port = 8428;
      runsOn = "pi";
      audience = "operator";
      exposeOnTailnet = false;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    tv = {
      port = 8989;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    vault = {
      port = 8222;
      runsOn = "aurora";
      audience = "family";
      exposeOnTailnet = true;
      auth = "oidc";
      monitored = true;
      dashboard = false;
    };
  };

  workloadsMatch = actualWorkloads == expectedWorkloads;
  routesMatch = actualRoutes == expectedRoutes;
in
if
  workloadsMatch
  && routesMatch
  && runtimePlacementCorrect
  && catalogVisibleEverywhere
  && lifecycleStateCorrect
  && papersFetchCompatibility
  && systemProfileRealizationCorrect
  && homeManagerRealizationCorrect
  && homeCapabilityProfilesCorrect
  && desktopCapabilityProfilesCorrect
  && riceInterfaceCorrect
then
  "ok — architecture workload placement + route behavior baseline unchanged"
else
  throw ''
    Architecture behavior baseline changed.

    Workload placement matches: ${toString workloadsMatch}
    Route fingerprints match:   ${toString routesMatch}
    Migrated runtime placement: ${toString runtimePlacementCorrect}
    Migrated catalog global:    ${toString catalogVisibleEverywhere}
    Lifecycle state correct:    ${toString lifecycleStateCorrect}
    Papers-fetch compatibility: ${toString papersFetchCompatibility}
    System profile realization: ${toString systemProfileRealizationCorrect}
    Home Manager realization:   ${toString homeManagerRealizationCorrect}
    Home capability profiles:   ${toString homeCapabilityProfilesCorrect}
    Desktop capabilities:       ${toString desktopCapabilityProfilesCorrect}
    Rice interface realization: ${toString riceInterfaceCorrect}

    Expected workloads: ${builtins.toJSON expectedWorkloads}
    Inventory workloads: ${builtins.toJSON actualWorkloads}
    Expected routes: ${builtins.toJSON expectedRoutes}
    Actual routes:   ${builtins.toJSON actualRoutes}

    If this is intentional, document the behavior change separately from the
    architecture refactor and update this baseline only with operator approval.
  ''
