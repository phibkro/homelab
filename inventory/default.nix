{ lib }:

/**
  Pure homelab inventory compiler.

  Runs before `lib.nixosSystem`, so module selection never depends on the NixOS
  `config` fixed point. Compiler-private paths stay under `internal`; callers
  and generated tools receive only `public` or a host-scoped `forHost`
  projection.
*/

let
  hosts = import ./hosts.nix;
  profiles = import ./profiles.nix;
  workloadCatalog = import ./workloads.nix { inherit lib; };
  datasets = import ./datasets.nix;

  hostNames = lib.attrNames hosts;
  nixosHostNames = lib.attrNames (lib.filterAttrs (_: host: host.kind == "nixos") hosts);
  profileNames = lib.attrNames profiles;
  workloadNames = lib.attrNames workloadCatalog;

  referencedProfiles = lib.unique (lib.concatMap (host: host.profiles) (lib.attrValues hosts));
  unknownProfiles = lib.subtractLists profileNames referencedProfiles;

  referencedWorkloads = lib.unique (
    lib.concatMap (profile: profile.workloads) (lib.attrValues profiles)
    ++ lib.concatMap (host: host.workloads) (lib.attrValues hosts)
  );
  unknownWorkloads = lib.subtractLists workloadNames referencedWorkloads;
  unusedWorkloads = lib.subtractLists referencedWorkloads workloadNames;

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
    lib.unique (
      lib.concatMap (profileName: profiles.${profileName}.systemModules) hosts.${hostName}.profiles
    );

  hostsForWorkload =
    workloadName: lib.filter (hostName: lib.elem workloadName (workloadsFor hostName)) hostNames;

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

  lanRoutes = lib.foldl' (
    routes: workloadName: routes // resolvedEndpointsFor workloadName
  ) { } workloadNames;

  runtimeModulesFor =
    hostName:
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
      if host.kind == "nixos" then
        "nixosConfigurations.${name}.config.system.build.toplevel"
      else
        "homeConfigurations.${name}.activationPackage";
  }) hosts;
  entryPlaneHosts = profileHosts.entry-plane;
  activationOrder = lib.subtractLists entryPlaneHosts nixosHostNames ++ entryPlaneHosts;

  publicDeployment = {
    targets = deploymentTargets;
    buildOrder = hostNames;
    inherit activationOrder;
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
  machineRootHosts = lib.mapAttrs' (
    name: _host: lib.nameValuePair "modules/machines/${name}" [ name ]
  ) hosts;

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
    inherit datasets;
    deployment = publicDeployment;
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
assert lib.assertMsg (unknownWorkloads == [ ])
  "inventory: profile/host workload reference(s) do not exist: ${lib.concatStringsSep ", " unknownWorkloads}";
assert lib.assertMsg (
  unusedWorkloads == [ ]
) "inventory: catalog workload(s) have no placement: ${lib.concatStringsSep ", " unusedWorkloads}";
assert lib.assertMsg (duplicateEndpoints == [ ])
  "inventory: endpoint name(s) have multiple owners: ${lib.concatStringsSep ", " duplicateEndpoints}";
assert lib.assertMsg (unknownDatasetWorkloads == [ ])
  "inventory: dataset producer/consumer workload reference(s) do not exist: ${lib.concatStringsSep ", " unknownDatasetWorkloads}";
assert lib.assertMsg (invalidDatasetPaths == { })
  "inventory: dataset storage.relativePath must be a non-empty relative path without '..': ${lib.concatStringsSep ", " (lib.attrNames invalidDatasetPaths)}";
assert lib.assertMsg (invalidArtifactWorkloads == { })
  "inventory: immutable artifact contract or governed legacy exception is invalid for workload(s): ${lib.concatStringsSep ", " (lib.attrNames invalidArtifactWorkloads)}";
{
  inherit public forHost deployment;

  internal = {
    inherit
      hosts
      profiles
      datasets
      workloadCatalog
      workloadsFor
      systemModulesFor
      runtimeModulesFor
      lanRoutes
      nixosHostNames
      ;
  };
}
