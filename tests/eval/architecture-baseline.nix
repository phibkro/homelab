{
  inputs,
  lib,
  ...
}:

/**
  Behavior baseline for the concern-oriented architecture migration.

  This test deliberately describes behavior, not implementation paths. During
  the migration `actualWorkloads` will switch from the legacy
  `nori.services.<name>.enabled` registry to resolved `nori.inventory`
  placement, while this expected projection remains unchanged.

  The route fingerprint covers the cross-host fields most likely to drift when
  catalog declarations move out of runtime modules. Rich adapter behavior is
  covered independently by the route, DNS, Gatus, and multi-host tests.
*/

let
  hosts = inputs.self.nixosConfigurations;

  enabledWorkloads =
    hostName:
    lib.attrNames (
      lib.filterAttrs (_: workload: workload.enabled) hosts.${hostName}.config.nori.services
    );

  legacyWorkloads = lib.genAttrs [
    "workstation"
    "aurora"
    "pi"
    "pavilion"
  ] enabledWorkloads;

  actualWorkloads = lib.mapAttrs (_: host: host.config.nori.inventory.currentWorkloads) hosts;

  expectedWorkloads = {
    workstation = [
      "bazarr"
      "beszel-agent"
      "blocky"
      "btrbk-replica-target"
      "disk-alert"
      "gatus"
      "jellyfin"
      "jellyseerr"
      "lidarr"
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

  hasJellyfinRuntime =
    host: host.config.nori.harden ? jellyfin && host.config.nori.backups ? jellyfin;
  runtimePlacementCorrect =
    hasJellyfinRuntime hosts.workstation
    && lib.all (hostName: !(hasJellyfinRuntime hosts.${hostName})) [
      "aurora"
      "pi"
      "pavilion"
    ];
  catalogVisibleEverywhere =
    lib.all
      (
        hostName:
        hosts.${hostName}.config.nori.inventory.workloads.jellyfin.endpoints.media.runsOn == "workstation"
      )
      [
        "workstation"
        "aurora"
        "pi"
        "pavilion"
      ];

  expectedRoutes = {
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
    status = {
      port = 8082;
      runsOn = "pi";
      audience = "public";
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

  inventoryMatchesLegacy = actualWorkloads == legacyWorkloads;
  workloadsMatch = actualWorkloads == expectedWorkloads;
  routesMatch = actualRoutes == expectedRoutes;
in
if
  inventoryMatchesLegacy
  && workloadsMatch
  && routesMatch
  && runtimePlacementCorrect
  && catalogVisibleEverywhere
then
  "ok — architecture workload placement + route behavior baseline unchanged"
else
  throw ''
    Architecture behavior baseline changed.

    Inventory matches legacy:   ${toString inventoryMatchesLegacy}
    Workload placement matches: ${toString workloadsMatch}
    Route fingerprints match:   ${toString routesMatch}
    Jellyfin runtime placement: ${toString runtimePlacementCorrect}
    Jellyfin catalog global:    ${toString catalogVisibleEverywhere}

    Expected workloads: ${builtins.toJSON expectedWorkloads}
    Inventory workloads: ${builtins.toJSON actualWorkloads}
    Legacy workloads:    ${builtins.toJSON legacyWorkloads}

    Expected routes: ${builtins.toJSON expectedRoutes}
    Actual routes:   ${builtins.toJSON actualRoutes}

    If this is intentional, document the behavior change separately from the
    architecture refactor and update this baseline only with operator approval.
  ''
