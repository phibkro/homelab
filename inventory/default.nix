{
  lib,
  hosts ? import ./hosts.nix,
  profiles ? import ../profiles/default.nix,
  workloadCatalog ? import ./workloads.nix { inherit lib; },
  datasets ? import ./datasets.nix,
  disks ? import ./disks.nix,
  site ? import ./site.nix,
  backup ? import ./backup.nix { inherit disks; },
  hostRoles ? import ./host-roles.nix,
  audiences ? import ../roles/audiences.nix,
}:

/**
  Pure homelab inventory compiler.

  Runs before `lib.nixosSystem`, so module selection never depends on the NixOS
  `config` fixed point. Compiler-private paths stay under `internal`; callers
  and generated tools receive only `public` or a host-scoped `forHost`
  projection.
*/

let
  hostNames = lib.attrNames hosts;
  nixosHostNames = lib.attrNames (lib.filterAttrs (_: host: host.kind == "nixos") hosts);
  supportedHostKinds = [
    "ansible"
    "nixos"
  ];
  supportedPlacementStrategies = [
    "all-matches"
    "first-unique"
  ];
  hostTags = lib.unique (lib.concatMap (host: host.tags or [ ]) (lib.attrValues hosts));
  profileNames = lib.attrNames profiles;
  workloadNames = lib.attrNames workloadCatalog;
  workloadIsActive = workload: workload.active or true;
  invalidWorkloadActivation = lib.filterAttrs (
    _name: workload: !builtins.isBool (workload.active or true)
  ) workloadCatalog;

  invalidDiskDeclarations = lib.filterAttrs (
    _name: disk:
    !(lib.elem (disk.role or null) [
      "backup"
      "cold-primary"
    ])
    || !lib.elem (disk.attachedHost or null) hostNames
    || (disk.mountPoint or "") == ""
    || !(disk ? identity)
    || !(disk ? filesystem)
    || !lib.hasPrefix "/dev/disk/by-id/" (disk.identity.byId or "")
    || !lib.hasPrefix "/dev/disk/by-id/" (disk.filesystem.device or "")
    || (disk.identity.model or "") == ""
    || (disk.identity.serial or "") == ""
    || (disk.identity.capacityBytes or 0) <= 0
    || !lib.elem (disk.identity.transport or null) [
      "sata"
      "usb"
    ]
    || (disk.filesystem.type or "") == ""
    || (disk.filesystem.label or "") == ""
  ) disks;
  duplicateDiskByIds = lib.filter (
    byId: lib.count (disk: disk.identity.byId == byId) (lib.attrValues disks) > 1
  ) (lib.unique (map (disk: disk.identity.byId) (lib.attrValues disks)));

  invalidHostRoles = lib.filterAttrs (_name: host: !lib.elem host.identity.role hostRoles) hosts;
  validSourceRoot =
    root: builtins.isString root && root != "" && !lib.hasPrefix "/" root && !lib.hasInfix ".." root;
  isStableName = name: builtins.isString name && builtins.match "[a-z0-9][a-z0-9-]*" name != null;
  invalidHardeningExceptions = lib.filterAttrs (
    _name: workload:
    workload ? _hardeningException
    && (!builtins.isString workload._hardeningException || workload._hardeningException == "")
  ) workloadCatalog;
  nonEmptyString = value: builtins.isString value && value != "";
  validStringList = values: builtins.isList values && lib.all nonEmptyString values;
  validHeaderName =
    value: nonEmptyString value && !lib.hasInfix "\n" value && !lib.hasInfix "\r" value;
  validHeaders =
    headers:
    builtins.isAttrs headers
    && lib.all validHeaderName (lib.attrNames headers)
    && lib.all (value: nonEmptyString value && !lib.hasInfix "\n" value && !lib.hasInfix "\r" value) (
      lib.attrValues headers
    );
  validMonitor =
    monitor:
    monitor == null
    || (
      builtins.isAttrs monitor
      && (!(monitor ? path) || (nonEmptyString monitor.path && lib.hasPrefix "/" monitor.path))
      && (!(monitor ? interval) || nonEmptyString monitor.interval)
      && (
        !(monitor ? failureThreshold)
        || (builtins.isInt monitor.failureThreshold && monitor.failureThreshold > 0)
      )
      && (!(monitor ? conditions) || validStringList monitor.conditions)
      && (!(monitor ? headers) || validHeaders monitor.headers)
      && (!(monitor ? routeHostHeader) || builtins.isBool monitor.routeHostHeader)
      && !((monitor.routeHostHeader or false) && builtins.hasAttr "Host" (monitor.headers or { }))
      && (!(monitor ? name) || isStableName monitor.name)
    );
  validForwardAuth =
    forwardAuth:
    forwardAuth == null
    || (
      builtins.isAttrs forwardAuth
      && (
        !(forwardAuth ? exemptPaths)
        || (builtins.isList forwardAuth.exemptPaths && lib.all nonEmptyString forwardAuth.exemptPaths)
      )
    );
  validOidc =
    oidc:
    oidc == null
    || (
      builtins.isAttrs oidc
      && nonEmptyString (oidc.clientName or "")
      && (nonEmptyString (oidc.redirectPath or "") && lib.hasPrefix "/" oidc.redirectPath)
      && lib.elem (oidc.tokenEndpointAuthMethod or null) [
        "client_secret_basic"
        "client_secret_post"
      ]
      && (!(oidc ? scopes) || validStringList oidc.scopes)
      && (!(oidc ? authorizationPolicy) || nonEmptyString oidc.authorizationPolicy)
      && (!(oidc ? secretEnvName) || nonEmptyString oidc.secretEnvName)
      && nonEmptyString (oidc.secretHashEnvName or "")
    );
  validDashboard =
    dashboard:
    dashboard == null
    || (
      builtins.isAttrs dashboard
      && nonEmptyString (dashboard.title or "")
      && nonEmptyString (dashboard.icon or "")
      && lib.elem (dashboard.group or null) [
        "Consume"
        "Acquire"
        "Personal"
        "Projects"
        "Admin"
      ]
      && nonEmptyString (dashboard.description or "")
      && (!(dashboard ? allowInsecure) || builtins.isBool dashboard.allowInsecure)
    );
  validEndpoint =
    endpoint:
    builtins.isAttrs endpoint
    && builtins.isInt (endpoint.port or 0)
    && endpoint.port > 0
    && endpoint.port < 65536
    && lib.elem (endpoint.scheme or "http") [
      "http"
      "https"
    ]
    && (!(endpoint ? exposeOnTailnet) || builtins.isBool endpoint.exposeOnTailnet)
    && lib.elem (endpoint.reachability or "internal") [
      "internal"
      "internet"
    ]
    && lib.elem (endpoint.audience or "operator") audiences.keys
    && (!(endpoint ? publicStatus) || builtins.isBool endpoint.publicStatus)
    && (
      !(endpoint ? noAuthReason) || endpoint.noAuthReason == null || nonEmptyString endpoint.noAuthReason
    )
    && validMonitor (endpoint.monitor or null)
    && validForwardAuth (endpoint.forwardAuth or null)
    && validOidc (endpoint.oidc or null)
    && !(endpoint ? oidc && endpoint ? forwardAuth)
    && validDashboard (endpoint.dashboard or null)
    && !(endpoint ? runsOn)
    && !(endpoint ? hostname);
  endpointDeclarationsFor =
    workload: if builtins.isAttrs (workload.endpoints or { }) then workload.endpoints or { } else { };
  invalidEndpointDeclarations = lib.filter (declaration: declaration != "") (
    lib.concatMap (
      workloadName:
      let
        workload = workloadCatalog.${workloadName};
        endpoints = endpointDeclarationsFor workload;
      in
      if !builtins.isAttrs (workload.endpoints or { }) then
        [ "${workloadName}.endpoints" ]
      else
        lib.mapAttrsToList (
          endpointName: endpoint:
          lib.optionalString (
            !(isStableName endpointName && validEndpoint endpoint)
          ) "${workloadName}.${endpointName}"
        ) endpoints
    ) workloadNames
  );
  validListener =
    listener:
    builtins.isAttrs listener
    && builtins.isInt (listener.port or 0)
    && listener.port > 0
    && listener.port < 65536;
  listenerDeclarationsFor =
    workload: if builtins.isAttrs (workload.listeners or { }) then workload.listeners or { } else { };
  invalidListenerDeclarations = lib.filter (declaration: declaration != "") (
    lib.concatMap (
      workloadName:
      let
        workload = workloadCatalog.${workloadName};
        listeners = listenerDeclarationsFor workload;
        listenerNames = lib.attrNames listeners;
      in
      if !builtins.isAttrs (workload.listeners or { }) then
        [ "${workloadName}.listeners" ]
      else
        lib.optional (lib.unique listenerNames != listenerNames) "${workloadName}.listeners"
        ++ lib.mapAttrsToList (
          listenerName: listener:
          lib.optionalString (
            !(isStableName listenerName && validListener listener)
          ) "${workloadName}.listeners.${listenerName}"
        ) listeners
    ) workloadNames
  );
  validProbe =
    probe:
    builtins.isAttrs probe
    && lib.elem (probe.scheme or null) [
      "http"
      "https"
      "tcp"
    ]
    && builtins.isInt (probe.port or 0)
    && probe.port > 0
    && probe.port < 65536
    && nonEmptyString (probe.interval or "")
    && validStringList (probe.conditions or [ ])
    && (!(probe ? path) || (nonEmptyString probe.path && lib.hasPrefix "/" probe.path));
  probeDeclarationsFor =
    workload: if builtins.isAttrs (workload._probes or { }) then workload._probes or { } else { };
  invalidProbeDeclarations = lib.filter (declaration: declaration != "") (
    lib.concatMap (
      workloadName:
      let
        workload = workloadCatalog.${workloadName};
        probes = probeDeclarationsFor workload;
      in
      if !builtins.isAttrs (workload._probes or { }) then
        [ "${workloadName}._probes" ]
      else
        lib.mapAttrsToList (
          probeName: probe:
          lib.optionalString (!(isStableName probeName && validProbe probe)) "${workloadName}.${probeName}"
        ) probes
    ) workloadNames
  );
  invalidProfileDeclarations = lib.filterAttrs (_name: profile: profile ? workloads) profiles;
  invalidHostDeclarations = lib.filterAttrs (
    _name: host:
    !lib.elem (host.kind or null) supportedHostKinds
    || !(host ? managementRoot)
    || host.managementRoot == ""
    || lib.hasPrefix "/" host.managementRoot
    || lib.hasInfix ".." host.managementRoot
    || !builtins.isList (host.tags or [ ])
    || !lib.all isStableName (host.tags or [ ])
    || lib.unique (host.tags or [ ]) != (host.tags or [ ])
    || host ? workloads
    || !builtins.isList (host.additionalSourceRoots or [ ])
    || !lib.all validSourceRoot (host.additionalSourceRoots or [ ])
    || (host.kind == "nixos" && (!(host ? systemModule) || !(host ? homeModule) || host ? deployment))
    || (
      host.kind == "ansible"
      && (
        host ? systemModule
        || host ? homeModule
        || !(host ? deployment)
        || (host.deployment.planCommand or "") == ""
        || (host.deployment.applyCommand or "") == ""
        || (host.deployment.verifyCommand or "") == ""
      )
    )
  ) hosts;

  referencedProfiles = lib.unique (lib.concatMap (host: host.profiles) (lib.attrValues hosts));
  unknownProfiles = lib.subtractLists profileNames referencedProfiles;

  selectorIsValid =
    selector:
    builtins.isAttrs selector
    && lib.length (lib.attrNames selector) == 1
    && (
      (selector ? host && builtins.isString selector.host && builtins.hasAttr selector.host hosts)
      || (
        selector ? tags
        && builtins.isList selector.tags
        && selector.tags != [ ]
        && lib.all isStableName selector.tags
        && lib.unique selector.tags == selector.tags
        && lib.all (tag: lib.elem tag hostTags) selector.tags
      )
      || (
        selector ? roles
        && builtins.isList selector.roles
        && selector.roles != [ ]
        && lib.all builtins.isString selector.roles
        && lib.unique selector.roles == selector.roles
        && lib.all (role: lib.elem role hostRoles) selector.roles
      )
    );
  placementIsValid =
    workload:
    let
      placement = workload.placement or null;
      cardinality = if builtins.isAttrs placement then placement.cardinality or null else null;
      strategy = if builtins.isAttrs placement then placement.strategy or null else null;
    in
    builtins.isAttrs placement
    &&
      lib.attrNames placement == [
        "cardinality"
        "selectors"
        "strategy"
      ]
    && lib.elem strategy supportedPlacementStrategies
    && builtins.isList placement.selectors
    && placement.selectors != [ ]
    && lib.all selectorIsValid placement.selectors
    && builtins.isAttrs cardinality
    &&
      lib.attrNames cardinality == [
        "max"
        "min"
      ]
    && builtins.isInt cardinality.min
    && cardinality.min >= 1
    && builtins.isInt cardinality.max
    && cardinality.max >= cardinality.min
    && (strategy != "first-unique" || (cardinality.min == 1 && cardinality.max == 1));
  invalidPlacementDeclarations = lib.filterAttrs (
    _: workload: !placementIsValid workload
  ) workloadCatalog;

  invalidHostRoleDeclarations = lib.filterAttrs (
    _name: workload:
    !(workload ? hostRoles)
    || !builtins.isList workload.hostRoles
    || workload.hostRoles == [ ]
    || !lib.all builtins.isString workload.hostRoles
    || lib.any (role: !lib.elem role hostRoles) workload.hostRoles
    || lib.unique workload.hostRoles != workload.hostRoles
  ) workloadCatalog;

  datasetWorkloadReferences = lib.unique (
    lib.concatMap (dataset: dataset.producers ++ dataset.consumers) (lib.attrValues datasets)
  );
  unknownDatasetWorkloads = lib.subtractLists workloadNames datasetWorkloadReferences;
  invalidDatasetPaths = lib.filterAttrs (
    _name: dataset:
    dataset.storage.relativePath == ""
    || lib.hasPrefix "/" dataset.storage.relativePath
    || lib.hasInfix ".." dataset.storage.relativePath
  ) datasets;

  artifactWorkloads = lib.filterAttrs (_: workload: workload ? artifact) workloadCatalog;
  invalidArtifactWorkloads = lib.filterAttrs (
    _name: workload:
    let
      inherit (workload) artifact;
      legacy = artifact.consumer.kind == "legacy-host-build";
      exception = artifact.legacyException or null;
    in
    artifact.source.repository == ""
    || artifact.source.ref == ""
    || (
      legacy
      && (
        artifact.immutable
        || (artifact.consumer.unit or null) == null
        || exception == null
        || exception.owner == ""
        || exception.reason == ""
        || exception.removalTrigger == ""
        || exception.verification == ""
      )
    )
    || (!legacy && (!artifact.immutable || artifact ? legacyException))
  ) artifactWorkloads;

  selectorHosts =
    selector:
    if selector ? host then
      [ selector.host ]
    else if selector ? tags then
      lib.filter (
        hostName: lib.all (tag: lib.elem tag (hosts.${hostName}.tags or [ ])) selector.tags
      ) hostNames
    else
      lib.filter (hostName: lib.elem hosts.${hostName}.identity.role selector.roles) hostNames;

  rawHostsForWorkload =
    workloadName:
    let
      placement = workloadCatalog.${workloadName}.placement;
      selectorResults = map selectorHosts placement.selectors;
      firstNonEmpty = lib.findFirst (matches: matches != [ ]) [ ] selectorResults;
    in
    if placement.strategy == "first-unique" then
      firstNonEmpty
    else
      lib.sort builtins.lessThan (lib.unique (lib.concatLists selectorResults));

  placementResolutionFailures = lib.concatMap (
    workloadName:
    let
      placement = workloadCatalog.${workloadName}.placement;
      selected = rawHostsForWorkload workloadName;
      count = lib.length selected;
      tooFew = count < placement.cardinality.min;
      tooMany = count > placement.cardinality.max;
      ambiguous = placement.strategy == "first-unique" && count > 1;
    in
    lib.optional (count == 0) "${workloadName}: no selector matched"
    ++ lib.optional ambiguous "${workloadName}: first non-empty selector matched multiple hosts [${lib.concatStringsSep ", " selected}]"
    ++
      lib.optional (count != 0 && tooFew)
        "${workloadName}: selected ${toString count} host(s), below minimum ${toString placement.cardinality.min}"
    ++
      lib.optional (count != 0 && tooMany)
        "${workloadName}: selected ${toString count} host(s), above maximum ${toString placement.cardinality.max}"
  ) workloadNames;

  hostsForWorkload = rawHostsForWorkload;

  workloadsFor =
    hostName:
    lib.filter (workloadName: lib.elem hostName (hostsForWorkload workloadName)) workloadNames;

  realizationId = workloadName: instanceName: "realization.${workloadName}.${instanceName}";
  activeWorkloadsFor =
    hostName:
    lib.filter (
      workloadName:
      workloadIsActive workloadCatalog.${workloadName}
      && lib.elem hostName (hostsForWorkload workloadName)
    ) workloadNames;
  realizationsFor =
    workloadName:
    let
      placement = workloadCatalog.${workloadName}.placement;
      selectedHosts = hostsForWorkload workloadName;
    in
    map (
      hostName:
      let
        instanceName = if placement.strategy == "first-unique" then "primary" else hostName;
      in
      {
        id = realizationId workloadName instanceName;
        inherit workloadName hostName instanceName;
      }
    ) selectedHosts;
  workloadRealizations = lib.genAttrs workloadNames realizationsFor;

  systemModulesFor =
    hostName:
    assert lib.assertMsg (
      hosts.${hostName}.kind == "nixos"
    ) "inventory.systemModulesFor: '${hostName}' is managed by ${hosts.${hostName}.kind}, not NixOS";
    lib.unique (
      lib.concatMap (profileName: profiles.${profileName}.systemModules) hosts.${hostName}.profiles
    );

  invalidRolePlacements = lib.concatMap (
    workloadName:
    let
      workload = workloadCatalog.${workloadName};
    in
    if builtins.hasAttr workloadName invalidHostRoleDeclarations then
      [ ]
    else
      lib.concatMap (
        hostName:
        let
          actualRole = hosts.${hostName}.identity.role;
        in
        lib.optional (!lib.elem actualRole workload.hostRoles) "${workloadName}@${hostName} (${actualRole})"
      ) (hostsForWorkload workloadName)
  ) workloadNames;

  resolvedEndpointsFor =
    workloadName:
    let
      workload = workloadCatalog.${workloadName};
      realizations = realizationsFor workloadName;
      endpoints = endpointDeclarationsFor workload;
    in
    assert lib.assertMsg (lib.all (endpoint: !(endpoint ? runsOn)) (lib.attrValues endpoints))
      "inventory: endpoint placement is derived from workload realizations; '${workloadName}' must not declare runsOn";
    assert lib.assertMsg (
      endpoints == { } || lib.length realizations == 1
    ) "inventory: endpoints on workload '${workloadName}' require exactly one realization";
    let
      resolvedHost = (builtins.head realizations).hostName;
    in
    lib.mapAttrs (
      endpointName: endpoint:
      endpoint
      // {
        runsOn = resolvedHost;
        hostname = "${endpointName}.${site.domain}";
      }
    ) endpoints;

  endpointNames = lib.concatMap (
    workloadName: lib.attrNames (endpointDeclarationsFor workloadCatalog.${workloadName})
  ) workloadNames;
  duplicateEndpoints = lib.filter (
    endpointName: lib.count (candidate: candidate == endpointName) endpointNames > 1
  ) (lib.unique endpointNames);
  invalidPublicStatusEndpoints = lib.concatMap (
    workloadName:
    lib.mapAttrsToList (endpointName: _endpoint: "${workloadName}.${endpointName}") (
      lib.filterAttrs (
        _endpointName: endpoint:
        (endpoint.publicStatus or false)
        && ((endpoint.monitor or null) == null || (endpoint.audience or "operator") == "operator")
      ) (endpointDeclarationsFor workloadCatalog.${workloadName})
    )
  ) workloadNames;

  lanRoutes = lib.foldl' (
    routes: workloadName: routes // resolvedEndpointsFor workloadName
  ) { } workloadNames;
  publicEdgeHostnames = [ "status.${site.domain}" ];
  edgeHostnameCollisions = lib.filter (
    endpointName: lib.elem "${endpointName}.${site.domain}" publicEdgeHostnames
  ) (lib.attrNames lanRoutes);

  runtimeModulesFor =
    hostName:
    assert lib.assertMsg (
      hosts.${hostName}.kind == "nixos"
    ) "inventory.runtimeModulesFor: '${hostName}' is managed by ${hosts.${hostName}.kind}, not NixOS";
    lib.unique (
      map (workloadName: workloadCatalog.${workloadName}.runtimeModule) (
        lib.filter (
          workloadName:
          workloadIsActive workloadCatalog.${workloadName} && workloadCatalog.${workloadName} ? runtimeModule
        ) (workloadsFor hostName)
      )
    );

  publicProfiles = lib.mapAttrs (_: profile: {
    inherit (profile) description;
  }) profiles;

  publicHosts = lib.mapAttrs (
    name: host:
    host.identity
    // {
      inherit (host) kind profiles tags;
      workloads = workloadsFor name;
    }
  ) hosts;

  publicWorkloads = lib.mapAttrs (
    name: workload:
    removeAttrs workload [
      "_manifestPath"
      "_hardeningException"
      "runtimeModule"
      "_probes"
      "topology"
    ]
    // {
      active = workload.active or true;
      hosts = hostsForWorkload name;
      realizations = map (realization: {
        inherit (realization) id;
        host = realization.hostName;
        instance = realization.instanceName;
      }) (realizationsFor name);
      endpoints = resolvedEndpointsFor name;
      listeners = listenerDeclarationsFor workload;
    }
  ) workloadCatalog;

  hostsForProfile =
    profileName: lib.filter (hostName: lib.elem profileName hosts.${hostName}.profiles) hostNames;
  profileHosts = lib.mapAttrs (name: _profile: hostsForProfile name) profiles;
  workloadHosts = lib.mapAttrs (name: _workload: hostsForWorkload name) workloadCatalog;

  topology = (import ./topology.nix { inherit lib; }) {
    inherit
      hosts
      workloadCatalog
      datasets
      disks
      workloadRealizations
      resolvedEndpointsFor
      ;
  };

  deploymentTargets = lib.mapAttrs (name: host: {
    inherit (host) kind profiles;
    workloads = workloadsFor name;
    buildAttribute =
      if host.kind == "nixos" then "nixosConfigurations.${name}.config.system.build.toplevel" else null;
    planCommand = if host.kind == "ansible" then host.deployment.planCommand else null;
    applyCommand = if host.kind == "ansible" then host.deployment.applyCommand else null;
    verifyCommand = if host.kind == "ansible" then host.deployment.verifyCommand else null;
  }) hosts;
  entryPlaneHosts = profileHosts.entry-plane;
  activationOrder = lib.subtractLists entryPlaneHosts hostNames ++ entryPlaneHosts;

  publicDeployment = {
    targets = deploymentTargets;
    buildOrder = nixosHostNames;
    inherit activationOrder;
  };

  authenticationFor =
    endpoint:
    if endpoint ? oidc then
      "oidc"
    else if endpoint ? forwardAuth then
      "forward-auth"
    else if endpoint ? noAuthReason then
      "service-native-or-exception"
    else
      "none";
  routeAuthFor =
    endpoint:
    if endpoint ? forwardAuth then
      "forward-auth"
    else if endpoint ? oidc then
      "oidc"
    else
      "none";
  normalizedMonitorFor =
    hostname: monitor:
    if monitor == null then
      null
    else
      {
        path = monitor.path or "/";
        interval = monitor.interval or "60s";
        headers =
          (monitor.headers or { })
          // lib.optionalAttrs (monitor.routeHostHeader or false) {
            Host = hostname;
          };
        conditions = monitor.conditions or [ "[STATUS] == 200" ];
        failureThreshold = monitor.failureThreshold or 3;
        name = monitor.name or null;
      };
  routeProjectionFor = workloadName: endpointName: endpoint: {
    name = endpointName;
    workload = workloadName;
    endpoint = endpointName;
    host = endpoint.runsOn;
    inherit (endpoint) hostname port;
    scheme = endpoint.scheme or "http";
    reachability = endpoint.reachability or "internal";
    audience = endpoint.audience or "operator";
    authentication = authenticationFor endpoint;
    auth = routeAuthFor endpoint;
    exposeOnTailnet = endpoint.exposeOnTailnet or false;
    forwardAuth = endpoint.forwardAuth or null;
    oidc = endpoint.oidc or null;
    monitor = normalizedMonitorFor endpoint.hostname (endpoint.monitor or null);
    dashboard = endpoint.dashboard or null;
    publicStatus = endpoint.publicStatus or false;
    upstreamHostHeader = endpoint.upstreamHostHeader or null;
    upstreamOriginHeader = endpoint.upstreamOriginHeader or null;
  };
  activeRoutes = lib.foldl' (
    routes: workloadName:
    if workloadIsActive workloadCatalog.${workloadName} then
      routes
      // lib.mapAttrs (endpointName: endpoint: routeProjectionFor workloadName endpointName endpoint) (
        resolvedEndpointsFor workloadName
      )
    else
      routes
  ) { } workloadNames;
  activeRouteValues = lib.attrValues activeRoutes;
  routeFor =
    endpointName:
    if builtins.hasAttr endpointName activeRoutes then activeRoutes.${endpointName} else null;
  routePortFor =
    endpointName:
    let
      route = routeFor endpointName;
    in
    if route == null then null else route.port;
  listenerPortFor =
    workloadName: listenerName:
    let
      listeners = listenerDeclarationsFor workloadCatalog.${workloadName};
    in
    assert lib.assertMsg (builtins.hasAttr listenerName listeners)
      "inventory: workload '${workloadName}' must declare private listener '${listenerName}'";
    listeners.${listenerName}.port;
  activeListenerPortFor =
    workloadName: listenerName:
    if workloadIsActive workloadCatalog.${workloadName} then
      listenerPortFor workloadName listenerName
    else
      null;
  privateListenerBindingsFor =
    hostName:
    lib.concatMap (
      workloadName:
      let
        workload = workloadCatalog.${workloadName};
      in
      if workloadIsActive workload && lib.elem hostName (hostsForWorkload workloadName) then
        lib.mapAttrsToList (listenerName: listener: {
          owner = "${workloadName}.listeners.${listenerName}";
          inherit (listener) port;
        }) (listenerDeclarationsFor workload)
      else
        [ ]
    ) workloadNames;
  routeBindingsFor =
    hostName:
    map (route: {
      owner = "${route.workload}.endpoints.${route.endpoint}";
      inherit (route) port;
    }) (lib.filter (route: route.host == hostName) activeRouteValues);
  portBindingsFor = hostName: routeBindingsFor hostName ++ privateListenerBindingsFor hostName;
  portCollisions = lib.concatMap (
    hostName:
    let
      bindings = portBindingsFor hostName;
      ports = map (binding: binding.port) bindings;
      duplicatePorts = lib.filter (port: lib.count (candidate: candidate == port) ports > 1) (
        lib.unique ports
      );
    in
    map (
      port:
      let
        owners = map (binding: binding.owner) (lib.filter (binding: binding.port == port) bindings);
      in
      "${hostName}:${toString port} (${lib.concatStringsSep ", " owners})"
    ) duplicatePorts
  ) hostNames;
  unsafeInternetOperatorRoutes = lib.attrNames (
    lib.filterAttrs (
      _name: route: route.reachability == "internet" && route.audience == "operator"
    ) activeRoutes
  );
  internetIdentityRoutes = lib.filterAttrs (
    _name: route: route.reachability == "internet" && (route.oidc != null || route.forwardAuth != null)
  ) activeRoutes;
  internetAuthAvailable = activeRoutes ? auth && activeRoutes.auth.reachability == "internet";
  activeForwardAuthRoutes = lib.filterAttrs (_: route: route.forwardAuth != null) activeRoutes;
  piHost = hosts.${site.entryPlaneHost};
  piLanAddress = piHost.identity.lanIp;
  piBackendAddressFor =
    route:
    if route.host == site.entryPlaneHost then piLanAddress else hosts.${route.host}.identity.tailnetIp;
  piRouteTargetFor =
    endpointName:
    let
      route = routeFor endpointName;
    in
    if route == null then null else "${piBackendAddressFor route}:${toString route.port}";
  piForwardAuthUpstream =
    if activeRoutes ? auth then "${piLanAddress}:${toString activeRoutes.auth.port}" else null;
  piRouteFor = route: {
    inherit (route)
      name
      hostname
      scheme
      reachability
      audience
      auth
      ;
    upstream_address = piBackendAddressFor route;
    upstream_port = route.port;
    forward_auth_exempt_paths =
      if route.forwardAuth == null then [ ] else route.forwardAuth.exemptPaths or [ ];
    forward_auth_upstream = if route.forwardAuth == null then null else piForwardAuthUpstream;
    oidc_redirect_path = if route.oidc == null then null else route.oidc.redirectPath;
    upstream_host_header = route.upstreamHostHeader;
    upstream_origin_header = route.upstreamOriginHeader;
  };
  piServiceRouteNames = lib.attrNames activeRoutes;
  piRouteNames =
    lib.optional (activeRoutes ? pihole) "pihole" ++ lib.remove "pihole" piServiceRouteNames;
  piServiceRoutes = map (name: piRouteFor activeRoutes.${name}) piRouteNames;
  piRoutes = piServiceRoutes;
  piTailnetWorkloadPorts = lib.sort builtins.lessThan (
    lib.unique (
      map (route: route.port) (
        lib.filter (route: route.host == site.entryPlaneHost && route.exposeOnTailnet) (
          lib.attrValues activeRoutes
        )
      )
    )
  );
  dashboardGroupOrder = [
    "Consume"
    "Acquire"
    "Personal"
    "Projects"
    "Admin"
  ];
  dashboardLinkFor = route: {
    inherit (route.dashboard) title icon description;
    url = "https://${route.hostname}";
  };
  dashboardGroups = lib.foldl' (
    groups: route:
    groups
    // {
      ${route.dashboard.group} = (groups.${route.dashboard.group} or [ ]) ++ [ (dashboardLinkFor route) ];
    }
  ) { } (lib.filter (route: route.dashboard != null) (lib.attrValues activeRoutes));
  glanceBookmarkGroups = lib.concatMap (
    group:
    lib.optional (builtins.hasAttr group dashboardGroups) {
      title = group;
      links = lib.sort (left: right: left.title < right.title) dashboardGroups.${group};
    }
  ) dashboardGroupOrder;
  oidcRoutes = lib.filterAttrs (_: route: route.oidc != null) activeRoutes;
  oidcClients = map (
    name:
    let
      route = oidcRoutes.${name};
      inherit (route) oidc;
    in
    {
      client_id = route.name;
      client_name = oidc.clientName;
      authorization_policy = oidc.authorizationPolicy or "one_factor";
      token_endpoint_auth_method = oidc.tokenEndpointAuthMethod;
      secret_hash_env_name = oidc.secretHashEnvName;
      redirect_uris = [ "https://${route.hostname}${oidc.redirectPath}" ];
      scopes =
        oidc.scopes or [
          "openid"
          "profile"
          "email"
          "groups"
        ];
    }
  ) (lib.attrNames oidcRoutes);
  routeProbeFor =
    route:
    let
      inherit (route) monitor;
    in
    {
      name = if monitor.name == null then route.name else monitor.name;
      url = "${route.scheme}://${piBackendAddressFor route}:${toString route.port}${monitor.path}";
      inherit (monitor) interval conditions;
      failure_threshold = monitor.failureThreshold;
      send_on_resolved = true;
    }
    // lib.optionalAttrs (monitor.headers != { }) { inherit (monitor) headers; };
  monitoredRoutes = lib.filterAttrs (_: route: route.monitor != null) activeRoutes;
  piholeAdminProbes = lib.optional (monitoredRoutes ? pihole) (routeProbeFor monitoredRoutes.pihole);
  routeProbes = map (name: routeProbeFor monitoredRoutes.${name}) (
    lib.remove "pihole" (lib.attrNames monitoredRoutes)
  );
  probeProjectionFor =
    workloadName: probeName: probe:
    let
      hostName = builtins.head (hostsForWorkload workloadName);
      host = hosts.${hostName};
      address =
        if hostName == site.entryPlaneHost && host.identity.lanIp != null then
          host.identity.lanIp
        else
          host.identity.tailnetIp;
      path = if probe.scheme == "tcp" then "" else probe.path or "/";
    in
    {
      name = probeName;
      url = "${probe.scheme}://${address}:${toString probe.port}${path}";
      inherit (probe) interval conditions;
      failure_threshold = 3;
      send_on_resolved = true;
    };
  workloadProbes = lib.concatMap (
    workloadName:
    let
      workload = workloadCatalog.${workloadName};
      probes = probeDeclarationsFor workload;
    in
    if workloadIsActive workload then
      map (probeName: probeProjectionFor workloadName probeName probes.${probeName}) (
        lib.attrNames probes
      )
    else
      [ ]
  ) workloadNames;
  explicitProbe =
    probe:
    probe
    // {
      failure_threshold = 3;
      send_on_resolved = true;
    };
  explicitProbes =
    workloadProbes
    ++ piholeAdminProbes
    ++ map explicitProbe [
      {
        name = "station-ssh";
        url = "tcp://${hosts.workstation.identity.lanIp}:22";
        interval = "60s";
        conditions = [ "[CONNECTED] == true" ];
      }
      {
        name = "entry-caddy";
        url = "http://${piLanAddress}";
        interval = "120s";
        client = {
          "ignore-redirect" = true;
        };
        conditions = [ "[STATUS] == 308" ];
      }
    ];
  exporterTargetsFor =
    workloadName: listenerName:
    if workloadIsActive workloadCatalog.${workloadName} then
      let
        port = listenerPortFor workloadName listenerName;
      in
      map (hostName: {
        target = "${hosts.${hostName}.identity.tailnetIp}:${toString port}";
        host = hostName;
      }) (hostsForWorkload workloadName)
    else
      [ ];
  nodeTargets = exporterTargetsFor "node-exporter" "node";
  processTargets = exporterTargetsFor "node-exporter" "process";
  gpuTargets = exporterTargetsFor "nvidia-gpu-exporter" "metrics";
  beszelAgentPort = activeListenerPortFor "beszel-agent" "agent";
  beszelSystems =
    if workloadIsActive workloadCatalog."beszel-agent" then
      map (
        hostName:
        let
          host = hosts.${hostName};
        in
        {
          name = hostName;
          host =
            if hostName == site.entryPlaneHost && host.identity.lanIp != null then
              host.identity.lanIp
            else
              host.identity.tailnetIp;
          port = beszelAgentPort;
        }
      ) (hostsForWorkload "beszel-agent")
    else
      [ ];
  gatusTarget = piRouteTargetFor "uptime";
  victoriametricsTarget = piRouteTargetFor "tsdb";
  victoriametricsScrapeJobs =
    if workloadIsActive workloadCatalog.victoriametrics then
      lib.optional (gatusTarget != null) {
        job_name = "gatus";
        static_configs = [ { targets = [ gatusTarget ]; } ];
      }
      ++ lib.optional (victoriametricsTarget != null) {
        job_name = "victoriametrics";
        static_configs = [ { targets = [ victoriametricsTarget ]; } ];
      }
      ++ lib.optional (nodeTargets != [ ]) {
        job_name = "node";
        static_configs = map (target: {
          targets = [ target.target ];
          labels = {
            inherit (target) host;
          };
        }) nodeTargets;
      }
      ++ lib.optional (processTargets != [ ]) {
        job_name = "process";
        static_configs = map (target: {
          targets = [ target.target ];
          labels = {
            inherit (target) host;
          };
        }) processTargets;
      }
      ++ lib.optional (gpuTargets != [ ]) {
        job_name = "nvidia-gpu";
        static_configs = map (target: {
          targets = [ target.target ];
          labels = {
            inherit (target) host;
          };
        }) gpuTargets;
      }
    else
      [ ];
  piHostRecords = lib.filter (record: record != null) (
    map (
      hostName:
      let
        lanIp = hosts.${hostName}.identity.lanIp;
      in
      if lanIp == null then
        null
      else
        {
          address = lanIp;
          names = [ "${hostName}.${site.domain}" ];
        }
    ) hostNames
  );
  piRouteRecords = map (route: {
    address = piLanAddress;
    names = [ route.hostname ] ++ map (domain: "${route.name}.${domain}") site.deprecatedDomains;
  }) piRoutes;
  dnsRecordKey = record: "${record.address}|${lib.concatStringsSep "|" record.names}";
  piDnsRecords = lib.sort (left: right: dnsRecordKey left < dnsRecordKey right) (
    piHostRecords ++ piRouteRecords
  );
  backupProjection =
    if backup.enabled then
      {
        pi_backup_enabled = true;
        pi_backup_target_address = hosts.${backup.targetHost}.identity.tailnetIp;
        pi_backup_target_host = backup.hostname;
        pi_backup_target_user = backup.pi.user;
        pi_backup_repository_prefix = backup.pi.repositoryPrefix;
        pi_backup_target_known_host = "${backup.hostname} ${backup.pi.hostKey}";
        pi_backup_jobs = backup.pi.jobs;
      }
    else
      { pi_backup_enabled = false; };
  piholeAdminPort = routePortFor "pihole";
  piholeDnsPort =
    if workloadIsActive workloadCatalog.pihole then
      workloadCatalog.pihole._probes.pihole-dns.port
    else
      null;
  workloadRunsOnPi =
    workloadName:
    workloadIsActive workloadCatalog.${workloadName}
    && lib.elem site.entryPlaneHost (hostsForWorkload workloadName);
  piProjection = {
    pi_lan_address = piLanAddress;
    pi_service_bind_address = piLanAddress;
    pihole_lan_address = piLanAddress;
    pihole_tailnet_address = piHost.identity.tailnetIp;
    pi_admin_port = piholeAdminPort;
    pi_dns_port = piholeDnsPort;
    pi_domain = site.domain;
    pi_deprecated_domains = site.deprecatedDomains;
    pi_routes = piRoutes;
    pi_tailnet_workload_ports = piTailnetWorkloadPorts;
    caddy_http_port = activeListenerPortFor "caddy" "http";
    caddy_https_port = activeListenerPortFor "caddy" "https";
    authelia_port = routePortFor "auth";
    beszel_bind_port = routePortFor "metrics";
    gatus_port = routePortFor "uptime";
    glance_port = routePortFor "home";
    ntfy_port = routePortFor "alert";
    vector_bind_port = activeListenerPortFor "victorialogs-server" "vector-api";
    victorialogs_bind_port = routePortFor "logs";
    victoriametrics_bind_port = routePortFor "tsdb";
    pihole_enabled = workloadRunsOnPi "pihole";
    caddy_enabled = workloadRunsOnPi "caddy";
    authelia_enabled = workloadRunsOnPi "authelia";
    glance_enabled = workloadRunsOnPi "glance";
    glance_bookmark_groups = glanceBookmarkGroups;
    ddns_enabled = workloadRunsOnPi "cloudflare-ddns";
    ntfy_enabled = workloadRunsOnPi "ntfy-server";
    victorialogs_enabled = workloadRunsOnPi "victorialogs-server";
    vector_enabled = workloadRunsOnPi "victorialogs-server";
    victoriametrics_enabled = workloadRunsOnPi "victoriametrics";
    beszel_enabled = workloadRunsOnPi "beszel-hub";
    beszel_agent_enabled = workloadRunsOnPi "beszel-agent";
    gatus_enabled = workloadRunsOnPi "gatus";
    heartbeat_enabled = workloadRunsOnPi "heartbeat";
    authelia_oidc_clients = oidcClients;
    gatus_endpoints = explicitProbes ++ routeProbes;
    victoriametrics_scrape_jobs = victoriametricsScrapeJobs;
    beszel_agent_listen_port = beszelAgentPort;
    beszel_systems = beszelSystems;
    ddns_hostnames = map (route: route.hostname) (
      lib.filter (route: route.reachability == "internet") piServiceRoutes
    );
    pihole_local_dns_records = piDnsRecords;
  }
  // backupProjection;

  presentationFor =
    endpointName: endpoint:
    let
      dashboard = endpoint.dashboard or null;
      audience = endpoint.audience or "operator";
    in
    {
      title = if dashboard == null then endpointName else dashboard.title;
      description = if dashboard == null then "" else dashboard.description;
      url = "https://${endpointName}.${site.domain}";
      inherit audience;
      inherit (endpoint) authentication;
      registrationRequired = audiences.registrationRequired audience;
      visibleTo = audiences.visibleToFor audience;
    };

  presentationCatalog = lib.mapAttrs presentationFor activeRoutes;
  dashboardEndpointNames = lib.attrNames (
    lib.filterAttrs (_name: endpoint: endpoint.dashboard != null) activeRoutes
  );
  statusEndpointNames = lib.attrNames (
    lib.filterAttrs (_name: endpoint: endpoint.publicStatus) activeRoutes
  );
  statusPresentationFor = endpointName: {
    inherit (presentationCatalog.${endpointName}) title description url;
  };

  status = {
    services = lib.genAttrs statusEndpointNames statusPresentationFor;
  };
  portal = {
    accessTiers = {
      public = "Visible without a homelab account";
      family = "Visible to registered family members and operators";
      operator = "Visible only to homelab operators";
    };
    services = lib.getAttrs dashboardEndpointNames presentationCatalog;
  };

  repoRoot = toString ../.;
  relativePathFor = path: lib.removePrefix "${repoRoot}/" (toString path);
  runtimeRootFor = workload: builtins.dirOf (relativePathFor workload.runtimeModule);
  manifestPathFor = workload: relativePathFor workload._manifestPath;
  addSourceRoot =
    roots: root: selectedHosts:
    roots
    // {
      ${root} = lib.unique ((roots.${root} or [ ]) ++ selectedHosts);
    };
  sourceRootHosts = lib.foldl' (
    roots: workloadName:
    let
      workload = workloadCatalog.${workloadName};
      selectedHosts = workloadHosts.${workloadName};
      rootsWithManifest = addSourceRoot roots (manifestPathFor workload) selectedHosts;
    in
    if !(workload ? runtimeModule) then
      rootsWithManifest
    else
      addSourceRoot rootsWithManifest (runtimeRootFor workload) selectedHosts
  ) { } workloadNames;
  machineRootHosts = lib.foldlAttrs (
    roots: name: host:
    lib.foldl' (
      current: root:
      current
      // {
        ${root} = lib.unique ((current.${root} or [ ]) ++ [ name ]);
      }
    ) roots ([ host.managementRoot ] ++ (host.additionalSourceRoots or [ ]))
  ) { } hosts;

  deployment = publicDeployment // {
    allHosts = hostNames;
    profiles = profileHosts;
    workloads = workloadHosts;
    sourceRoots = sourceRootHosts;
    machineRoots = machineRootHosts;
  };

  public = {
    hosts = publicHosts;
    profiles = publicProfiles;
    workloads = publicWorkloads;
    routes = activeRoutes;
    inherit topology;
    inherit datasets disks backup;
    deployment = publicDeployment;
    inherit site status portal;
  };

  forHost =
    hostName:
    assert lib.assertMsg (lib.elem hostName hostNames) "inventory.forHost: unknown host '${hostName}'";
    public
    // {
      currentHost = hostName;
      currentWorkloads = activeWorkloadsFor hostName;
      routes = activeRoutes;
    };
in
assert lib.assertMsg (
  unknownProfiles == [ ]
) "inventory: host profile reference(s) do not exist: ${lib.concatStringsSep ", " unknownProfiles}";
assert lib.assertMsg (invalidProfileDeclarations == { })
  "inventory: profiles must not own workload placement: ${lib.concatStringsSep ", " (lib.attrNames invalidProfileDeclarations)}";
assert lib.assertMsg (invalidHostDeclarations == { })
  "inventory: hosts must declare unique stable tags, exactly one supported management backend, and a safe managementRoot: ${lib.concatStringsSep ", " (lib.attrNames invalidHostDeclarations)}";
assert lib.assertMsg (invalidHostRoles == { })
  "inventory: host roles must be drawn from [${lib.concatStringsSep ", " hostRoles}]: ${lib.concatStringsSep ", " (lib.attrNames invalidHostRoles)}";
assert lib.assertMsg (invalidPlacementDeclarations == { })
  "inventory: workloads must declare valid ordered placement selectors and cardinality: ${lib.concatStringsSep ", " (lib.attrNames invalidPlacementDeclarations)}";
assert lib.assertMsg (invalidWorkloadActivation == { })
  "inventory: workload active must be an explicit boolean: ${lib.concatStringsSep ", " (lib.attrNames invalidWorkloadActivation)}";
assert lib.assertMsg (invalidEndpointDeclarations == [ ])
  "inventory: malformed endpoint or monitor declaration(s): ${lib.concatStringsSep ", " invalidEndpointDeclarations}";
assert lib.assertMsg (invalidListenerDeclarations == [ ])
  "inventory: malformed private listener declaration(s): ${lib.concatStringsSep ", " invalidListenerDeclarations}";
assert lib.assertMsg (invalidProbeDeclarations == [ ])
  "inventory: malformed workload probe declaration(s): ${lib.concatStringsSep ", " invalidProbeDeclarations}";
assert lib.assertMsg (placementResolutionFailures == [ ])
  "inventory: workload placement resolution failed:\n${
    lib.concatStringsSep "\n" (map (failure: "- ${failure}") placementResolutionFailures)
  }";
assert lib.assertMsg (invalidDiskDeclarations == { })
  "inventory: external disks must have a known host, by-id identity, filesystem contract, and supported role: ${lib.concatStringsSep ", " (lib.attrNames invalidDiskDeclarations)}";
assert lib.assertMsg (duplicateDiskByIds == [ ])
  "inventory: external disks must not share a whole-disk by-id identity: ${lib.concatStringsSep ", " duplicateDiskByIds}";
assert lib.assertMsg (invalidHostRoleDeclarations == { })
  "inventory: workload hostRoles must be a non-empty list drawn from [${lib.concatStringsSep ", " hostRoles}]: ${lib.concatStringsSep ", " (lib.attrNames invalidHostRoleDeclarations)}";
assert lib.assertMsg (invalidHardeningExceptions == { })
  "inventory: _hardeningException must be a non-empty reason: ${lib.concatStringsSep ", " (lib.attrNames invalidHardeningExceptions)}";
assert lib.assertMsg (invalidRolePlacements == [ ])
  "inventory: workload placement violates its declared hostRoles: ${lib.concatStringsSep ", " invalidRolePlacements}";
assert lib.assertMsg (duplicateEndpoints == [ ])
  "inventory: endpoint name(s) have multiple owners: ${lib.concatStringsSep ", " duplicateEndpoints}";
assert lib.assertMsg (portCollisions == [ ])
  "inventory: resolved route/private listener port collision(s): ${lib.concatStringsSep ", " portCollisions}";
assert lib.assertMsg (unsafeInternetOperatorRoutes == [ ])
  "inventory: internet routes cannot use the operator audience: ${lib.concatStringsSep ", " unsafeInternetOperatorRoutes}";
assert lib.assertMsg (
  internetIdentityRoutes == { } || internetAuthAvailable
) "inventory: internet routes using identity require an internet-reachable auth route";
assert lib.assertMsg (edgeHostnameCollisions == [ ])
  "inventory: lanRoute hostname(s) collide with edge-owned domain(s): ${
    lib.concatStringsSep ", " (map (name: "${name}.${site.domain}") edgeHostnameCollisions)
  }";
assert lib.assertMsg (
  activeForwardAuthRoutes == { } || activeRoutes ? auth
) "inventory: active forward-auth routes require an active auth endpoint";
assert lib.assertMsg (invalidPublicStatusEndpoints == [ ])
  "inventory: publicStatus endpoints must be monitored and non-operator: ${lib.concatStringsSep ", " invalidPublicStatusEndpoints}";
assert lib.assertMsg (unknownDatasetWorkloads == [ ])
  "inventory: dataset producer/consumer workload reference(s) do not exist: ${lib.concatStringsSep ", " unknownDatasetWorkloads}";
assert lib.assertMsg (invalidDatasetPaths == { })
  "inventory: dataset storage.relativePath must be a non-empty relative path without '..': ${lib.concatStringsSep ", " (lib.attrNames invalidDatasetPaths)}";
assert lib.assertMsg (invalidArtifactWorkloads == { })
  "inventory: immutable artifact contract or governed legacy exception is invalid for workload(s): ${lib.concatStringsSep ", " (lib.attrNames invalidArtifactWorkloads)}";
assert lib.assertMsg (entryPlaneHosts == [ site.entryPlaneHost ])
  "inventory: site.entryPlaneHost must be the only host selecting the entry-plane profile (site=${site.entryPlaneHost}; profiles=${lib.concatStringsSep ", " entryPlaneHosts})";
builtins.deepSeq topology {
  inherit public forHost deployment;

  internal = {
    inherit
      hosts
      profiles
      datasets
      disks
      backup
      site
      workloadCatalog
      realizationsFor
      workloadRealizations
      workloadsFor
      activeWorkloadsFor
      activeRoutes
      piProjection
      systemModulesFor
      runtimeModulesFor
      lanRoutes
      nixosHostNames
      ;
  };
}
