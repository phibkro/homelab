{ inputs, lib }:

/**
  Private listener declarations are compiler-owned facts: invalid declarations
  fail before backend projection, while resolved endpoints, Pi scrape jobs, and
  NixOS firewall ports all consume the same catalog.
*/

let
  catalog = import ../../inventory/workloads.nix { inherit lib; };
  compile = workloadCatalog: import ../../inventory/default.nix { inherit lib workloadCatalog; };
  evaluate =
    workloadCatalog: builtins.tryEval (builtins.deepSeq (compile workloadCatalog).public true);

  invalidListenerPortCatalog = lib.recursiveUpdate catalog {
    "node-exporter".listeners.node.port = 0;
  };
  invalidHighListenerPortCatalog = lib.recursiveUpdate catalog {
    "node-exporter".listeners.node.port = 65536;
  };
  invalidListenerShapeCatalog = lib.recursiveUpdate catalog {
    "nvidia-gpu-exporter".listeners.metrics.port = "not-a-port";
  };
  invalidListenerContainerCatalog = lib.recursiveUpdate catalog {
    "beszel-agent".listeners = "not-an-attrset";
  };
  routeListenerCollisionCatalog = lib.recursiveUpdate catalog {
    "node-exporter".listeners.node.port = catalog.ollama.endpoints.ai.port;
  };
  inactiveGatusCatalog = lib.recursiveUpdate catalog {
    gatus.active = false;
  };

  compiled = compile catalog;
  inventory = compiled.public;
  piProjection = compiled.internal.piProjection;
  inactiveGatus = compile inactiveGatusCatalog;

  jobFor = name:
    lib.findFirst (job: job.job_name == name) null piProjection.victoriametrics_scrape_jobs;
  targetsFor = name:
    let
      job = jobFor name;
    in
    if job == null then [ ] else lib.concatMap (staticConfig: staticConfig.targets) job.static_configs;
  listenerTargetsFor = workloadName: listenerName:
    let
      port = inventory.workloads.${workloadName}.listeners.${listenerName}.port;
    in
    map (hostName: "${inventory.hosts.${hostName}.tailnetIp}:${toString port}") (
      inventory.workloads.${workloadName}.hosts
    );
  routeTargetFor = endpointName:
    let
      route = inventory.routes.${endpointName};
      address =
        if route.host == inventory.site.entryPlaneHost then
          inventory.hosts.${route.host}.lanIp
        else
          inventory.hosts.${route.host}.tailnetIp;
    in
    "${address}:${toString route.port}";
  routePortsForHost = hostName:
    lib.sort builtins.lessThan (
      lib.unique (
        map (route: route.port) (
          lib.filter (
            route: route.host == hostName && route.exposeOnTailnet
          ) (lib.attrValues inventory.routes)
        )
      )
    );
  firewallPortsForHost = hostName:
    inputs.self.nixosConfigurations.${hostName}.config.networking.firewall.interfaces."tailscale0".allowedTCPPorts;

  canonicalListenerProjection =
    inventory.workloads."node-exporter".listeners.node.port == 9100
    && inventory.workloads."node-exporter".listeners.process.port == 9256
    && inventory.workloads."nvidia-gpu-exporter".listeners.metrics.port == 9835
    && inventory.workloads."beszel-agent".listeners.agent.port == 45876
    && inventory.workloads."victorialogs-server".listeners.vector-api.port == 8686
    && lib.length inventory.workloads."node-exporter".hosts > 1;
  canonicalEndpointProjection =
    inventory.workloads.gatus.endpoints.uptime.hostname == "uptime.${inventory.site.domain}"
    && inventory.workloads.victoriametrics.endpoints.tsdb.hostname == "tsdb.${inventory.site.domain}"
    && inventory.workloads."victorialogs-server".endpoints.logs.hostname == "logs.${inventory.site.domain}";
  scrapeProjection =
    lib.all (target: lib.elem target (targetsFor "node")) (listenerTargetsFor "node-exporter" "node")
    && lib.all (target: lib.elem target (targetsFor "process")) (listenerTargetsFor "node-exporter" "process")
    && lib.all (target: lib.elem target (targetsFor "nvidia-gpu")) (
      listenerTargetsFor "nvidia-gpu-exporter" "metrics"
    )
    && lib.elem (routeTargetFor "uptime") (targetsFor "gatus")
    && lib.elem (routeTargetFor "tsdb") (targetsFor "victoriametrics");
  piProjectionUsesListeners =
    piProjection.vector_bind_port == inventory.workloads."victorialogs-server".listeners.vector-api.port
    && piProjection.beszel_systems != [ ]
    && lib.all (
      system: system.port == inventory.workloads."beszel-agent".listeners.agent.port
    ) piProjection.beszel_systems;
  routeFirewallsExposeLocalRoutes =
    let
      nixosHostNames = lib.attrNames inputs.self.nixosConfigurations;
    in
    lib.any (hostName: routePortsForHost hostName != [ ]) nixosHostNames
    && lib.all (
      hostName:
      lib.all (port: lib.elem port (firewallPortsForHost hostName)) (routePortsForHost hostName)
    ) nixosHostNames;
  inactivePiWorkloadProjection =
    !inactiveGatus.public.workloads.gatus.active
    && !(inactiveGatus.public.routes ? uptime)
    && !inactiveGatus.internal.piProjection.gatus_enabled
    && inactiveGatus.internal.piProjection.gatus_port == null
    && !(lib.any (route: route.name == "uptime") inactiveGatus.internal.piProjection.pi_routes);
  invalidListenerDeclarationsRejected = lib.all (result: !result.success) [
    (evaluate invalidListenerPortCatalog)
    (evaluate invalidHighListenerPortCatalog)
    (evaluate invalidListenerShapeCatalog)
    (evaluate invalidListenerContainerCatalog)
    (evaluate routeListenerCollisionCatalog)
  ];
in
if
  canonicalListenerProjection
  && canonicalEndpointProjection
  && scrapeProjection
  && piProjectionUsesListeners
  && routeFirewallsExposeLocalRoutes
  && inactivePiWorkloadProjection
  && invalidListenerDeclarationsRejected
then
  "ok — listener declarations, endpoint hostnames, firewall ports, and Pi projections share one compiler contract"
else
  throw ''
    Listener projection contract failed.
    canonical listeners: ${toString canonicalListenerProjection}
    canonical endpoints: ${toString canonicalEndpointProjection}
    scrape projection: ${toString scrapeProjection}
    Pi listener projection: ${toString piProjectionUsesListeners}
    route firewalls: ${toString routeFirewallsExposeLocalRoutes}
    inactive Pi workload: ${toString inactivePiWorkloadProjection}
    invalid declarations: ${toString invalidListenerDeclarationsRejected}
  ''
