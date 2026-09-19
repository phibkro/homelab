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
  inventory = inputs.self.lib.noriInventory;
  compiledInventory = import ../../inventory { inherit lib; };
  hosts = inputs.self.nixosConfigurations;
  homes = {
    workstation = hosts.workstation.config.home-manager.users.nori;
  };
  qbittorrentServerConfig = hosts.workstation.config.services.qbittorrent.serverConfig;
  qbittorrentPreStart = hosts.workstation.config.systemd.services.qbittorrent.preStart;

  hasHomePackage =
    homeName: packageName:
    lib.any (package: lib.getName package == packageName) homes.${homeName}.home.packages;

  agentSoulPath = ../../users/nori/programs/agent-soul/SOUL.md;
  agentSoul = builtins.readFile agentSoulPath;
  agentHarnessesShareSoul =
    homes.workstation.home.file.".claude/CLAUDE.md".source == agentSoulPath
    && lib.all (path: lib.hasPrefix agentSoul homes.workstation.home.file.${path}.text) [
      ".codex/AGENTS.md"
      ".omp/agent/AGENTS.md"
    ];

  actualWorkloads = lib.mapAttrs (_: host: host.workloads) inventory.hosts;

  expectedWorkloads = {
    adelie = [
      "beszel-agent"
      "node-exporter"
    ];
    pi = [
      "authelia"
      "beszel-agent"
      "beszel-hub"
      "caddy"
      "cloudflare-ddns"
      "gatus"
      "heartbeat"
      "ntfy-notify"
      "ntfy-server"
      "pihole"
      "victorialogs-server"
      "victoriametrics"
    ];
    workstation = [
      "attic"
      "bazarr"
      "beszel-agent"
      "calibre-web"
      "clamor"
      "disk-alert"
      "filmder"
      "glance"
      "grafana"
      "heim"
      "herdr-projects-mcp"
      "hindsight"
      "immich"
      "jellyfin"
      "jellyseerr"
      "komga"
      "lidarr"
      "mcp-origin-tunnel"
      "miniflux"
      "music-ingest"
      "navidrome"
      "node-exporter"
      "ntfy-notify"
      "nvidia-gpu-exporter"
      "ollama"
      "open-webui"
      "paperless"
      "prowlarr"
      "qbittorrent"
      "radarr"
      "radicale"
      "recyclarr"
      "restic-target"
      "samba"
      "sonarr"
      "stremio"
      "suwayomi"
      "syncthing"
      "vaultwarden"
    ];
  };

  authMode =
    route:
    if (route.oidc or null) != null then
      "oidc"
    else if (route.forwardAuth or null) != null then
      "forward-auth"
    else if (route.noAuthReason or null) != null then
      "exception"
    else
      "none";

  routeFingerprint = route: {
    inherit (route) port runsOn;
    audience = route.audience or "operator";
    exposeOnTailnet = route.exposeOnTailnet or false;
    auth = authMode route;
    monitored = (route.monitor or null) != null;
    dashboard = (route.dashboard or null) != null;
  };

  actualRoutes = lib.mapAttrs (_: routeFingerprint) compiledInventory.internal.lanRoutes;

  migratedRuntimePlacements = {
    authelia = [ "pi" ];
    bazarr = [ "workstation" ];
    beszel-agent = [
      "adelie"
      "pi"
      "workstation"
    ];
    beszel-hub = [ "pi" ];
    pihole = [ "pi" ];
    caddy = [ "pi" ];
    calibre-web = [ "workstation" ];
    disk-alert = [ "workstation" ];
    filmder = [ "workstation" ];
    glance = [ "workstation" ];
    grafana = [ "workstation" ];
    gatus = [ "pi" ];
    heartbeat = [ "pi" ];
    heim = [ "workstation" ];
    immich = [ "workstation" ];
    jellyfin = [ "workstation" ];
    jellyseerr = [ "workstation" ];
    komga = [ "workstation" ];
    lidarr = [ "workstation" ];
    miniflux = [ "workstation" ];
    music-ingest = [ "workstation" ];
    navidrome = [ "workstation" ];
    node-exporter = [
      "adelie"
      "workstation"
    ];
    nvidia-gpu-exporter = [ "workstation" ];
    ntfy-notify = [
      "pi"
      "workstation"
    ];
    ntfy-server = [ "pi" ];
    ollama = [ "workstation" ];
    open-webui = [ "workstation" ];
    paperless = [ "workstation" ];
    prowlarr = [ "workstation" ];
    qbittorrent = [ "workstation" ];
    radarr = [ "workstation" ];
    radicale = [ "workstation" ];
    recyclarr = [ "workstation" ];
    samba = [ "workstation" ];
    sonarr = [ "workstation" ];
    stremio = [ "workstation" ];
    suwayomi = [ "workstation" ];
    syncthing = [ "workstation" ];
    vaultwarden = [ "workstation" ];
    victorialogs-server = [ "pi" ];
    victoriametrics = [ "pi" ];
  };

  runtimeEvidenceNames = {
    beszel-hub = "beszel";
    ntfy-notify = "notify";
    ntfy-server = "ntfy";
    victorialogs-server = "victorialogs";
  };
  runtimeEvidenceName = workloadName: runtimeEvidenceNames.${workloadName} or workloadName;
  hasMigratedRuntime =
    workloadName: host: builtins.hasAttr (runtimeEvidenceName workloadName) host.config.nori.backups;
  runtimePlacementCorrect = lib.all (
    workloadName:
    lib.all (
      hostName:
      hasMigratedRuntime workloadName hosts.${hostName}
      == lib.elem hostName migratedRuntimePlacements.${workloadName}
    ) (lib.attrNames hosts)
  ) (lib.attrNames migratedRuntimePlacements);

  migratedCatalogEndpoints = {
    authelia.auth = "pi";
    bazarr.subtitles = "workstation";
    beszel-hub.metrics = "pi";
    ntfy-server.alert = "pi";
    calibre-web.books = "workstation";
    clamor.agents = "workstation";
    filmder.filmder = "workstation";
    glance.home = "workstation";
    grafana.ops = "workstation";
    gatus.uptime = "pi";
    heim.heim = "workstation";
    immich.photos = "workstation";
    jellyfin.media = "workstation";
    jellyseerr.requests = "workstation";
    komga.comics = "workstation";
    lidarr.music = "workstation";
    miniflux.news = "workstation";
    navidrome.audio = "workstation";
    ollama.ai = "workstation";
    paperless.papers = "workstation";
    prowlarr.indexers = "workstation";
    qbittorrent.downloads = "workstation";
    radarr.movies = "workstation";
    radicale.calendar = "workstation";
    sonarr.tv = "workstation";
    stremio.stremio = "workstation";
    suwayomi.manga = "workstation";
    syncthing.sync = "workstation";
    victorialogs-server.logs = "pi";
    victoriametrics.tsdb = "pi";
    vaultwarden.vault = "workstation";
  };
  catalogVisibleEverywhere = lib.all (
    workloadName:
    lib.all (
      endpointName:
      inventory.workloads.${workloadName}.endpoints.${endpointName}.runsOn
      == migratedCatalogEndpoints.${workloadName}.${endpointName}
    ) (lib.attrNames migratedCatalogEndpoints.${workloadName})
  ) (lib.attrNames migratedCatalogEndpoints);

  lifecycleStateCorrect =
    inventory.workloads.ollama.active
    && !inventory.workloads.open-webui.active
    && inventory.workloads.open-webui.endpoints == { }
    && inventory.workloads.qbittorrent.active
    && inventory.workloads.qbittorrent.endpoints.downloads.runsOn == "workstation"
    && hosts.workstation.config.services.qbittorrent.enable
    && qbittorrentServerConfig == { }
    && hosts.workstation.config.systemd.services.qbittorrent.serviceConfig.UMask == "0002"
    && lib.hasInfix "qbt-configure.py" qbittorrentPreStart
    && lib.hasInfix "/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf" qbittorrentPreStart
    && lib.hasInfix "${hosts.workstation.config.nori.fs.downloads.path}/.downloads/complete" qbittorrentPreStart
    && lib.hasInfix "${hosts.workstation.config.nori.inventory.hosts.pi.tailnetIp}/32" qbittorrentPreStart
    && inventory.workloads.qbittorrent.endpoints.downloads.forwardAuth.exemptPaths == [ ]
    && compiledInventory.internal.lanRoutes.downloads.forwardAuth.exemptPaths == [ ]
    && lib.elem "d /var/lib/qBittorrent/qBittorrent/incomplete 0755 qbittorrent qbittorrent -" hosts.workstation.config.systemd.tmpfiles.rules;

  papersFetchCompatibility = lib.all (
    hostName:
    lib.any (
      package: lib.getName package == "papers-fetch"
    ) hosts.${hostName}.config.environment.systemPackages == (hostName == "workstation")
  ) (lib.attrNames hosts);

  systemProfileRealizationCorrect = hosts.workstation.config.programs.hyprland.enable;

  homeManagerRealizationCorrect =
    hosts.workstation.config.home-manager.users.nori.home.stateVersion == "26.05";

  homeCapabilityProfilesCorrect =
    lib.all (homeName: hasHomePackage homeName "just" && hasHomePackage homeName "devenv") (
      lib.attrNames homes
    )
    && lib.all (homeName: hasHomePackage homeName "gh" == lib.elem homeName [ "workstation" ]) (
      lib.attrNames homes
    )
    && lib.all (
      homeName:
      builtins.hasAttr ".claude/settings.json" homes.${homeName}.home.file
      == lib.elem homeName [ "workstation" ]
    ) (lib.attrNames homes)
    && homes.workstation.nori.agentNotify.enable
    && homes.workstation.nori.saturationAlert.enable
    && builtins.hasAttr ".codex/AGENTS.md" homes.workstation.home.file
    && lib.all (packageName: hasHomePackage "workstation" packageName) [
      # `pagu` replaced `agent-dispatch` as the agent-launch surface
      # (docs/decisions/0008). Assert the launcher the guidance names is
      # actually installed — that mismatch is what the ADR was written for.
      "pagu"
      "bubblewrap"
      "deno"
    ];

  desktopCapabilityProfilesCorrect = lib.all (packageName: hasHomePackage "workstation" packageName) [
    "ghostty"
    "davinci-resolve"
    "audacity"
    "discord"
    "zotero"
  ];

  riceInterfaceCorrect =
    hosts.workstation.config.home-manager.users.nori.nori.hyprRice.enable
    && hosts.workstation.config.home-manager.users.nori.wayland.windowManager.hyprland.enable;

  cacheContractCorrect =
    let
      cacheUrl = "https://cache.${hosts.workstation.config.nori.domain}/nori";
      cacheKey = "attic.nori.lan-1:3zt/aS8K1bSEjNvZQB9ga9OeZTxcRkvbb7aYRI/vobo=";
      everyHostSubscribes = lib.all (
        host:
        lib.elem cacheUrl host.config.nix.settings.extra-substituters
        && lib.elem cacheKey host.config.nix.settings.extra-trusted-public-keys
      ) (lib.attrValues hosts);
      workstation = hosts.workstation.config;
      workstationPublishes =
        workstation.systemd.timers.attic-cache-watch.wantedBy == [ "timers.target" ]
        && workstation.systemd.timers.attic-cache-seed.wantedBy == [ "timers.target" ]
        && workstation.systemd.services.attic-cache-watch.serviceConfig.Type == "exec"
        && workstation.systemd.services.attic-cache-seed.serviceConfig.Type == "exec"
        && workstation.systemd.services.attic-cache-watch.serviceConfig.RestartMode == "direct"
        && workstation.systemd.services.attic-cache-seed.serviceConfig.RestartMode == "direct";
      adelie = hosts.adelie.config;
      adelieCannotPublish =
        !(builtins.hasAttr "attic-push-token" adelie.sops.secrets)
        && !(builtins.hasAttr "attic-cache-watch" adelie.systemd.services)
        && !(builtins.hasAttr "attic-cache-seed" adelie.systemd.services);
    in
    everyHostSubscribes
    && workstationPublishes
    && adelieCannotPublish
    && workstation.services.atticd.enable
    && workstation.services.atticd.settings.storage.path == "/mnt/backup-local/attic"
    && workstation.services.atticd.settings.garbage-collection.default-retention-period == "30 days"
    && workstation.systemd.services.attic-cache-bootstrap.wantedBy == [ "multi-user.target" ];

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
      port = 8091;
      runsOn = "pi";
      audience = "operator";
      exposeOnTailnet = false;
      auth = "none";
      monitored = true;
      dashboard = false;
    };
    audio = {
      port = 4533;
      runsOn = "workstation";
      audience = "family";
      exposeOnTailnet = true;
      # Native Navidrome accounts rather than Authelia OIDC (70398f9).
      auth = "exception";
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
      runsOn = "workstation";
      audience = "family";
      exposeOnTailnet = true;
      auth = "forward-auth";
      monitored = true;
      dashboard = true;
    };
    cache = {
      port = 5000;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "exception";
      monitored = true;
      dashboard = false;
    };
    calendar = {
      port = 5232;
      runsOn = "workstation";
      audience = "family";
      exposeOnTailnet = true;
      auth = "exception";
      monitored = true;
      dashboard = true;
    };
    comics = {
      port = 8085;
      runsOn = "workstation";
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
      auth = "forward-auth";
      monitored = true;
      dashboard = true;
    };
    filmder = {
      port = 9092;
      runsOn = "workstation";
      audience = "public";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    heim = {
      port = 9094;
      runsOn = "workstation";
      audience = "public";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    home = {
      port = 8086;
      runsOn = "workstation";
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
      runsOn = "workstation";
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
    memory-origin = {
      port = 9078;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "exception";
      monitored = false;
      dashboard = false;
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
      runsOn = "workstation";
      audience = "family";
      exposeOnTailnet = true;
      auth = "oidc";
      monitored = true;
      dashboard = false;
    };
    ops = {
      port = 3000;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    papers = {
      port = 28981;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = true;
      dashboard = true;
    };
    photos = {
      port = 2283;
      runsOn = "workstation";
      audience = "family";
      exposeOnTailnet = true;
      auth = "oidc";
      monitored = true;
      dashboard = true;
    };
    projects-origin = {
      port = 9081;
      runsOn = "workstation";
      audience = "operator";
      exposeOnTailnet = true;
      auth = "none";
      monitored = false;
      dashboard = false;
    };
    requests = {
      port = 5055;
      runsOn = "workstation";
      audience = "family";
      exposeOnTailnet = true;
      # Native Jellyseerr accounts rather than Authelia OIDC (70398f9).
      auth = "exception";
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
      runsOn = "workstation";
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
  && agentHarnessesShareSoul
  && desktopCapabilityProfilesCorrect
  && riceInterfaceCorrect
  && cacheContractCorrect
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
    Agent harnesses share SOUL:  ${toString agentHarnessesShareSoul}
    Desktop capabilities:       ${toString desktopCapabilityProfilesCorrect}
    Rice interface realization: ${toString riceInterfaceCorrect}
    Cache server + clients:       ${toString cacheContractCorrect}

    Expected workloads: ${builtins.toJSON expectedWorkloads}
    Inventory workloads: ${builtins.toJSON actualWorkloads}
    Expected routes: ${builtins.toJSON expectedRoutes}
    Actual routes:   ${builtins.toJSON actualRoutes}

    If this is intentional, document the behavior change separately from the
    architecture refactor and update this baseline only with operator approval.
  ''
