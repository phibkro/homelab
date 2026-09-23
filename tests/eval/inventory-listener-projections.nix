{ inputs, lib }:

/**
  Private listener declarations are compiler-owned facts: invalid declarations
  fail before backend projection, while resolved endpoints, Pi scrape jobs, and
  NixOS firewall ports all consume the same catalog.
*/

let
  catalog = import ../../src/inventory/workloads.nix { inherit lib; };
  compile = workloadCatalog: import ../../src/inventory/default.nix { inherit lib workloadCatalog; };
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
  invalidProbeListenerCatalog = lib.recursiveUpdate catalog {
    pihole._probes.pihole-dns.listener = "missing";
  };
  ambiguousProbePortCatalog = lib.recursiveUpdate catalog {
    pihole._probes.pihole-dns.port = 53;
  };
  inactiveGatusCatalog = lib.recursiveUpdate catalog {
    gatus.active = false;
  };
  offPiBeszelAgentCatalog = lib.recursiveUpdate catalog {
    "beszel-agent".placement = {
      strategy = "all-matches";
      selectors = [ { roles = [ "workhorse" ]; } ];
      cardinality = {
        min = 2;
        max = 2;
      };
    };
  };

  compiled = compile catalog;
  inventory = compiled.public;
  piProjection = compiled.internal.piProjection;
  inactiveGatus = compile inactiveGatusCatalog;
  offPiBeszelAgent = compile offPiBeszelAgentCatalog;

  jobFor =
    name: lib.findFirst (job: job.job_name == name) null piProjection.victoriametrics_scrape_jobs;
  targetsFor =
    name:
    let
      job = jobFor name;
    in
    if job == null then [ ] else lib.concatMap (staticConfig: staticConfig.targets) job.static_configs;
  endpointFor =
    name: lib.findFirst (endpoint: endpoint.name == name) null piProjection.gatus_endpoints;
  listenerTargetsFor =
    workloadName: listenerName:
    let
      port = inventory.workloads.${workloadName}.listeners.${listenerName}.port;
    in
    map (
      hostName: "${inventory.hosts.${hostName}.tailnetIp}:${toString port}"
    ) inventory.workloads.${workloadName}.hosts;
  routeTargetFor =
    endpointName:
    let
      route = inventory.routes.${endpointName};
      address =
        if route.host == inventory.site.entryPlaneHost then
          inventory.hosts.${route.host}.lanIp
        else
          inventory.hosts.${route.host}.tailnetIp;
    in
    "${address}:${toString route.port}";
  routePortsForHost =
    hostName:
    lib.sort builtins.lessThan (
      lib.unique (
        map (route: route.port) (
          lib.filter (route: route.host == hostName && route.exposeOnTailnet) (
            lib.attrValues inventory.routes
          )
        )
      )
    );
  firewallPortsForHost =
    hostName:
    inputs.self.nixosConfigurations.${hostName}.config.networking.firewall.interfaces."tailscale0".allowedTCPPorts;

  canonicalListenerProjection =
    inventory.workloads."node-exporter".listeners.node.port == 9100
    && inventory.workloads."node-exporter".listeners.process.port == 9256
    && inventory.workloads."nvidia-gpu-exporter".listeners.metrics.port == 9835
    && inventory.workloads."beszel-agent".listeners.agent.port == 45876
    && inventory.workloads."victorialogs-server".listeners.vector-api.port == 8686
    && inventory.workloads.pihole.listeners.dns.port == 53
    && lib.length inventory.workloads."node-exporter".hosts > 1;
  canonicalEndpointProjection =
    inventory.workloads.gatus.endpoints.uptime.hostname == "uptime.${inventory.site.domain}"
    && inventory.workloads.gatus.endpoints.status.hostname == "status.${inventory.site.domain}"
    && inventory.workloads.victoriametrics.endpoints.tsdb.hostname == "tsdb.${inventory.site.domain}"
    &&
      inventory.workloads."victorialogs-server".endpoints.logs.hostname
      == "logs.${inventory.site.domain}";
  entryPlaneProjection =
    inventory.site == {
      domain = "home.phibkro.org";
      deprecatedDomains = [ "nori.lan" ];
      entryPlaneHost = "pi";
    }
    && inventory.hosts.${inventory.site.entryPlaneHost}.kind == "ansible"
    && !(builtins.hasAttr inventory.site.entryPlaneHost inputs.self.nixosConfigurations)
    && lib.all (endpoint: endpoint.runsOn == inventory.site.entryPlaneHost) [
      inventory.workloads.authelia.endpoints.auth
      inventory.workloads."beszel-hub".endpoints.metrics
      inventory.workloads.gatus.endpoints.status
      inventory.workloads.gatus.endpoints.uptime
      inventory.workloads.glance.endpoints.home
      inventory.workloads."ntfy-server".endpoints.alert
      inventory.workloads.victoriametrics.endpoints.tsdb
      inventory.workloads."victorialogs-server".endpoints.logs
    ];
  scrapeProjection =
    lib.all (target: lib.elem target (targetsFor "node")) (listenerTargetsFor "node-exporter" "node")
    && lib.all (target: lib.elem target (targetsFor "process")) (
      listenerTargetsFor "node-exporter" "process"
    )
    && lib.all (target: lib.elem target (targetsFor "nvidia-gpu")) (
      listenerTargetsFor "nvidia-gpu-exporter" "metrics"
    )
    && lib.elem (routeTargetFor "uptime") (targetsFor "gatus")
    && lib.elem (routeTargetFor "tsdb") (targetsFor "victoriametrics");
  piProjectionUsesListeners =
    piProjection.vector_bind_port == inventory.workloads."victorialogs-server".listeners.vector-api.port
    && piProjection.pi_dns_port == inventory.workloads.pihole.listeners.dns.port
    && piProjection.beszel_systems != [ ]
    && lib.all (
      system: system.port == inventory.workloads."beszel-agent".listeners.agent.port
    ) piProjection.beszel_systems
    && piProjection.gatus_public_enabled
    && piProjection.caddy_internet_enabled
    && piProjection.gatus_public_port == inventory.workloads.gatus.endpoints.status.port
    &&
      map (endpoint: endpoint.name) piProjection.gatus_public_endpoints == [
        "Navidrome"
        "Jellyfin"
        "Seerr"
      ];
  outcomeMonitoringProjection =
    let
      dnsProbe = endpointFor "pihole-dns-answer";
      authProbe = endpointFor "edge-auth-discovery";
      authBoundaryProbe = endpointFor "edge-auth-challenge";
      edgeProbes = map endpointFor [
        "edge-audio"
        "edge-media"
        "edge-requests"
      ];
      directDiagnosticProbes = map endpointFor [
        "auth"
        "audio"
        "media"
        "requests"
        "pihole-admin"
      ];
    in
    dnsProbe != null
    && dnsProbe.dns."query-name" == "media.${inventory.site.domain}"
    &&
      dnsProbe.conditions == [
        "[DNS_RCODE] == NOERROR"
        "[BODY] == ${inventory.hosts.pi.lanIp}"
      ]
    && authProbe != null
    && authProbe.client."dns-resolver" == "tcp://${inventory.hosts.pi.lanIp}:53"
    && authProbe.alert == false
    && lib.elem "[CERTIFICATE_EXPIRATION] > 168h" authProbe.conditions
    && authBoundaryProbe != null
    && authBoundaryProbe.client."ignore-redirect"
    && authBoundaryProbe.client."dns-resolver" == "tcp://${inventory.hosts.pi.lanIp}:53"
    && lib.elem "[STATUS] == 401" authBoundaryProbe.conditions
    && endpointFor "pihole-dns" == null
    && lib.all (endpoint: endpoint != null && endpoint.alert == false) directDiagnosticProbes
    && lib.all (
      endpoint:
      endpoint != null
      && endpoint.client."dns-resolver" == "tcp://${inventory.hosts.pi.lanIp}:53"
      && lib.elem "[CERTIFICATE_EXPIRATION] > 168h" endpoint.conditions
    ) edgeProbes;
  routeFirewallsExposeLocalRoutes =
    let
      nixosHostNames = lib.attrNames inputs.self.nixosConfigurations;
    in
    lib.any (hostName: routePortsForHost hostName != [ ]) nixosHostNames
    && lib.all (
      hostName: lib.all (port: lib.elem port (firewallPortsForHost hostName)) (routePortsForHost hostName)
    ) nixosHostNames;
  inactivePiWorkloadProjection =
    !inactiveGatus.public.workloads.gatus.active
    && !(inactiveGatus.public.routes ? uptime)
    && !(inactiveGatus.public.routes ? status)
    && !inactiveGatus.internal.piProjection.gatus_enabled
    && inactiveGatus.internal.piProjection.gatus_port == null
    && !inactiveGatus.internal.piProjection.gatus_public_enabled
    && inactiveGatus.internal.piProjection.gatus_public_port == null
    && inactiveGatus.internal.piProjection.gatus_public_endpoints == [ ]
    && !(lib.any (route: route.name == "uptime") inactiveGatus.internal.piProjection.pi_routes);
  hostLocalPiProjection =
    !offPiBeszelAgent.internal.piProjection.beszel_agent_enabled
    && offPiBeszelAgent.internal.piProjection.beszel_agent_listen_port == null;
  invalidListenerDeclarationsRejected = lib.all (result: !result.success) [
    (evaluate invalidListenerPortCatalog)
    (evaluate invalidHighListenerPortCatalog)
    (evaluate invalidListenerShapeCatalog)
    (evaluate invalidListenerContainerCatalog)
    (evaluate invalidProbeListenerCatalog)
    (evaluate ambiguousProbePortCatalog)
    (evaluate routeListenerCollisionCatalog)
  ];
in
if
  canonicalListenerProjection
  && canonicalEndpointProjection
  && entryPlaneProjection
  && scrapeProjection
  && piProjectionUsesListeners
  && outcomeMonitoringProjection
  && routeFirewallsExposeLocalRoutes
  && inactivePiWorkloadProjection
  && hostLocalPiProjection
  && invalidListenerDeclarationsRejected
then
  "ok — listener declarations, endpoint hostnames, firewall ports, and Pi projections share one compiler contract"
else
  throw ''
    Listener projection contract failed.
    canonical listeners: ${toString canonicalListenerProjection}
    outcome monitoring projection: ${toString outcomeMonitoringProjection}
    canonical endpoints: ${toString canonicalEndpointProjection}
    entry plane: ${toString entryPlaneProjection}
    scrape projection: ${toString scrapeProjection}
    Pi listener projection: ${toString piProjectionUsesListeners}
    route firewalls: ${toString routeFirewallsExposeLocalRoutes}
    inactive Pi workload: ${toString inactivePiWorkloadProjection}
    host-local Pi projection: ${toString hostLocalPiProjection}
    invalid declarations: ${toString invalidListenerDeclarationsRejected}
  ''
