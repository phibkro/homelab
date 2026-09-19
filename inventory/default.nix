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
  profileNames = lib.attrNames profiles;
  workloadNames = lib.attrNames workloadCatalog;

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
  invalidHostDeclarations = lib.filterAttrs (
    _name: host:
    !lib.elem (host.kind or null) supportedHostKinds
    || !(host ? managementRoot)
    || host.managementRoot == ""
    || lib.hasPrefix "/" host.managementRoot
    || lib.hasInfix ".." host.managementRoot
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

  referencedWorkloads = lib.unique (
    lib.concatMap (profile: profile.workloads) (lib.attrValues profiles)
    ++ lib.concatMap (host: host.workloads) (lib.attrValues hosts)
  );
  unknownWorkloads = lib.subtractLists workloadNames referencedWorkloads;
  unusedWorkloads = lib.subtractLists referencedWorkloads workloadNames;

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

  workloadsFor =
    hostName:
    let
      host = hosts.${hostName};
    in
    lib.sort builtins.lessThan (
      lib.unique (
        lib.concatMap (profileName: profiles.${profileName}.workloads) host.profiles ++ host.workloads
      )
    );

  systemModulesFor =
    hostName:
    assert lib.assertMsg (
      hosts.${hostName}.kind == "nixos"
    ) "inventory.systemModulesFor: '${hostName}' is managed by ${hosts.${hostName}.kind}, not NixOS";
    lib.unique (
      lib.concatMap (profileName: profiles.${profileName}.systemModules) hosts.${hostName}.profiles
    );

  hostsForWorkload =
    workloadName: lib.filter (hostName: lib.elem workloadName (workloadsFor hostName)) hostNames;

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
      endpoints = workload.endpoints or { };
      placements = hostsForWorkload workloadName;
      resolveEndpoint =
        endpointName: endpoint:
        let
          explicitHost = endpoint.runsOn or null;
          resolvedHost = if explicitHost != null then explicitHost else lib.head placements;
        in
        assert lib.assertMsg (explicitHost != null || lib.length placements == 1)
          "inventory: endpoint '${endpointName}' on multi-host workload '${workloadName}' must declare runsOn";
        assert lib.assertMsg (lib.elem resolvedHost placements)
          "inventory: endpoint '${endpointName}' on workload '${workloadName}' runs on '${resolvedHost}', which is not a placement host";
        endpoint // { runsOn = resolvedHost; };
    in
    lib.mapAttrs resolveEndpoint endpoints;

  endpointNames = lib.concatMap (
    workloadName: lib.attrNames (workloadCatalog.${workloadName}.endpoints or { })
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
      ) (workloadCatalog.${workloadName}.endpoints or { })
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
        lib.filter (workloadName: workloadCatalog.${workloadName} ? runtimeModule) (workloadsFor hostName)
      )
    );

  profilesForWorkload =
    workloadName:
    lib.attrNames (lib.filterAttrs (_: profile: lib.elem workloadName profile.workloads) profiles);

  publicProfiles = lib.mapAttrs (_: profile: {
    inherit (profile) description workloads;
  }) profiles;

  publicHosts = lib.mapAttrs (
    name: host:
    host.identity
    // {
      inherit (host) kind profiles;
      workloads = workloadsFor name;
    }
  ) hosts;

  publicWorkloads = lib.mapAttrs (
    name: workload:
    removeAttrs workload [ "runtimeModule" ]
    // {
      active = workload.active or true;
      hosts = hostsForWorkload name;
      profiles = profilesForWorkload name;
      endpoints = resolvedEndpointsFor name;
    }
  ) workloadCatalog;

  hostsForProfile =
    profileName: lib.filter (hostName: lib.elem profileName hosts.${hostName}.profiles) hostNames;
  profileHosts = lib.mapAttrs (name: _profile: hostsForProfile name) profiles;
  workloadHosts = lib.mapAttrs (name: _workload: hostsForWorkload name) workloadCatalog;

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
      authentication = authenticationFor endpoint;
      registrationRequired = audiences.registrationRequired audience;
      visibleTo = audiences.visibleToFor audience;
    };

  presentationCatalog = lib.mapAttrs presentationFor lanRoutes;
  dashboardEndpointNames = lib.attrNames (
    lib.filterAttrs (_name: endpoint: (endpoint.dashboard or null) != null) lanRoutes
  );
  statusEndpointNames = lib.attrNames (
    lib.filterAttrs (_name: endpoint: endpoint.publicStatus or false) lanRoutes
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
  runtimeRootFor =
    workload:
    let
      relativeModule = lib.removePrefix "${repoRoot}/" (toString workload.runtimeModule);
    in
    builtins.dirOf relativeModule;
  sourceRootHosts = lib.foldl' (
    roots: workloadName:
    let
      workload = workloadCatalog.${workloadName};
    in
    if !(workload ? runtimeModule) then
      roots
    else
      let
        root = runtimeRootFor workload;
      in
      roots
      // {
        ${root} = lib.unique ((roots.${root} or [ ]) ++ workloadHosts.${workloadName});
      }
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
      currentWorkloads = workloadsFor hostName;
    };
in
assert lib.assertMsg (
  unknownProfiles == [ ]
) "inventory: host profile reference(s) do not exist: ${lib.concatStringsSep ", " unknownProfiles}";
assert lib.assertMsg (invalidHostDeclarations == { })
  "inventory: hosts must declare exactly one supported management backend and a safe managementRoot: ${lib.concatStringsSep ", " (lib.attrNames invalidHostDeclarations)}";
assert lib.assertMsg (invalidHostRoles == { })
  "inventory: host roles must be drawn from [${lib.concatStringsSep ", " hostRoles}]: ${lib.concatStringsSep ", " (lib.attrNames invalidHostRoles)}";
assert lib.assertMsg (invalidDiskDeclarations == { })
  "inventory: external disks must have a known host, by-id identity, filesystem contract, and supported role: ${lib.concatStringsSep ", " (lib.attrNames invalidDiskDeclarations)}";
assert lib.assertMsg (duplicateDiskByIds == [ ])
  "inventory: external disks must not share a whole-disk by-id identity: ${lib.concatStringsSep ", " duplicateDiskByIds}";
assert lib.assertMsg (unknownWorkloads == [ ])
  "inventory: profile/host workload reference(s) do not exist: ${lib.concatStringsSep ", " unknownWorkloads}";
assert lib.assertMsg (
  unusedWorkloads == [ ]
) "inventory: catalog workload(s) have no placement: ${lib.concatStringsSep ", " unusedWorkloads}";
assert lib.assertMsg (invalidHostRoleDeclarations == { })
  "inventory: workload hostRoles must be a non-empty list drawn from [${lib.concatStringsSep ", " hostRoles}]: ${lib.concatStringsSep ", " (lib.attrNames invalidHostRoleDeclarations)}";
assert lib.assertMsg (invalidRolePlacements == [ ])
  "inventory: workload placement violates its declared hostRoles: ${lib.concatStringsSep ", " invalidRolePlacements}";
assert lib.assertMsg (duplicateEndpoints == [ ])
  "inventory: endpoint name(s) have multiple owners: ${lib.concatStringsSep ", " duplicateEndpoints}";
assert lib.assertMsg (edgeHostnameCollisions == [ ])
  "inventory: lanRoute hostname(s) collide with edge-owned domain(s): ${
    lib.concatStringsSep ", " (map (name: "${name}.${site.domain}") edgeHostnameCollisions)
  }";
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
{
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
      workloadsFor
      systemModulesFor
      runtimeModulesFor
      lanRoutes
      nixosHostNames
      ;
  };
}
