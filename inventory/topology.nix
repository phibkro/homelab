{ lib }:
{
  hosts,
  workloadCatalog,
  datasets,
  disks,
  workloadHosts,
  resolvedEndpointsFor,
}:
let
  schema = import ../lib/topology/schema.nix;
  inherit (schema) capabilityPropertySchemas relationshipTypeSegments;
  jsonScalarType =
    value:
    if builtins.isString value then
      "string"
    else if builtins.isInt value then
      "integer"
    else if builtins.isFloat value then
      "float"
    else if builtins.isBool value then
      "boolean"
    else if builtins.isNull value then
      "nil"
    else
      null;
  isJsonScalar =
    value:
    builtins.isBool value
    || builtins.isFloat value
    || builtins.isInt value
    || builtins.isNull value
    || builtins.isString value;

  isStableName = name: builtins.isString name && builtins.match "[a-z0-9][a-z0-9-]*" name != null;
  isTypedName =
    prefix: name:
    builtins.isString name && lib.hasPrefix prefix name && lib.removePrefix prefix name != "";

  hostId = name: "host.${name}";
  deviceId = name: "device.${name}";
  workloadId = name: "workload.${name}";
  endpointId = workloadName: endpointName: "endpoint.${workloadName}.${endpointName}";
  datasetId = name: "dataset.${name}";

  unsupportedKeys = allowed: value: lib.filter (name: !lib.elem name allowed) (lib.attrNames value);
  relationshipSegment =
    type:
    let
      segment = relationshipTypeSegments.${type} or null;
    in
    if builtins.isNull segment then
      throw "topology: unsupported relationship type '${type}'"
    else
      segment;
  relationshipId =
    {
      type,
      source,
      target,
      requirementName ? null,
    }:
    "relationship.${relationshipSegment type}.${source}.${target}${
      lib.optionalString (!builtins.isNull requirementName) ".${requirementName}"
    }";
  mkRelationship = args: {
    id = relationshipId args;
    inherit (args) type source target;
    properties = { };
    requirementName = args.requirementName or null;
  };

  requirementId =
    requirement: "${requirement.owner}.requirement.${requirement.name}@${requirement.target}";
  sortById = values: lib.sort (left: right: builtins.lessThan left.id right.id) values;
  duplicateIds =
    values:
    let
      ids = map (value: value.id) values;
    in
    lib.filter (id: lib.count (value: value.id == id) values > 1) (lib.unique ids);
  formatFailures =
    title: failures:
    "topology: ${title}:\n${lib.concatStringsSep "\n" (map (failure: "- ${failure}") failures)}";

  workloadNames = lib.attrNames workloadCatalog;
  datasetNames = lib.attrNames datasets;

  topologyDeclarationsOf =
    owner: allowedKeys: declaration:
    let
      topology = declaration.topology or { };
      unexpectedKeys = if builtins.isAttrs topology then unsupportedKeys allowedKeys topology else [ ];
    in
    assert lib.assertMsg (builtins.isAttrs topology)
      "topology: ${owner} topology declaration must be an attrset";
    assert lib.assertMsg (unexpectedKeys == [ ])
      "topology: ${owner} topology declaration has unsupported fields ${builtins.toJSON unexpectedKeys}";
    topology;
  capabilitiesOf =
    owner: allowedTopologyKeys: declaration:
    let
      topology = topologyDeclarationsOf owner allowedTopologyKeys declaration;
      capabilities = topology.capabilities or { };
    in
    assert lib.assertMsg (builtins.isAttrs capabilities)
      "topology: ${owner} capabilities must be an attrset";
    capabilities;
  hostCapabilitiesOf =
    hostName:
    let
      capabilities = hosts.${hostName}.capabilities or { };
    in
    assert lib.assertMsg (builtins.isAttrs capabilities)
      "topology: ${hostId hostName} capabilities must be an attrset";
    capabilities;
  requirementsOf =
    workloadName:
    let
      topology = topologyDeclarationsOf (workloadId workloadName) [
        "capabilities"
        "requires"
      ] workloadCatalog.${workloadName};
      requirements = topology.requires or { };
    in
    assert lib.assertMsg (builtins.isAttrs requirements)
      "topology: ${workloadId workloadName} requirements must be an attrset";
    requirements;

  endpointPropertyNames = [
    "port"
    "audience"
    "exposeOnTailnet"
    "publicStatus"
    "reachability"
    "runsOn"
  ];
  endpointProperties =
    endpoint: lib.filterAttrs (name: _: lib.elem name endpointPropertyNames) endpoint;

  hostNodes = lib.mapAttrsToList (hostName: host: {
    id = hostId hostName;
    kind = "machine";
    properties = host.identity // {
      managementBackend = host.kind;
    };
    capabilities = hostCapabilitiesOf hostName;
  }) hosts;
  deviceNodes = lib.mapAttrsToList (diskName: disk: {
    id = deviceId diskName;
    kind = "device";
    properties = removeAttrs disk [ "attachedHost" ];
    capabilities = { };
  }) disks;
  workloadNodes = lib.mapAttrsToList (workloadName: workload: {
    id = workloadId workloadName;
    kind = "workload";
    properties = removeAttrs workload [
      "endpoints"
      "runtimeModule"
      "topology"
    ];
    capabilities = capabilitiesOf (workloadId workloadName) [
      "capabilities"
      "requires"
    ] workload;
  }) workloadCatalog;
  endpointNodes = lib.concatMap (
    workloadName:
    lib.mapAttrsToList (endpointName: endpoint: {
      id = endpointId workloadName endpointName;
      kind = "endpoint";
      properties = endpointProperties endpoint;
      capabilities = capabilitiesOf (endpointId workloadName endpointName) [ "capabilities" ] endpoint;
    }) (resolvedEndpointsFor workloadName)
  ) workloadNames;
  datasetNodes = lib.mapAttrsToList (datasetName: dataset: {
    id = datasetId datasetName;
    kind = "dataset";
    properties = removeAttrs dataset [
      "producers"
      "consumers"
    ];
    capabilities = { };
  }) datasets;
  nodes = sortById (hostNodes ++ deviceNodes ++ workloadNodes ++ endpointNodes ++ datasetNodes);
  nodeIndex = builtins.listToAttrs (
    map (node: {
      name = node.id;
      value = node;
    }) nodes
  );

  isStableNodeId =
    node:
    let
      segments = lib.splitString "." node.id;
    in
    if node.kind == "machine" then
      lib.length segments == 2
      && builtins.elemAt segments 0 == "host"
      && isStableName (builtins.elemAt segments 1)
    else if node.kind == "device" then
      lib.length segments == 2
      && builtins.elemAt segments 0 == "device"
      && isStableName (builtins.elemAt segments 1)
    else if node.kind == "workload" then
      lib.length segments == 2
      && builtins.elemAt segments 0 == "workload"
      && isStableName (builtins.elemAt segments 1)
    else if node.kind == "endpoint" then
      lib.length segments == 3
      && builtins.elemAt segments 0 == "endpoint"
      && isStableName (builtins.elemAt segments 1)
      && isStableName (builtins.elemAt segments 2)
    else if node.kind == "dataset" then
      lib.length segments == 2
      && builtins.elemAt segments 0 == "dataset"
      && isStableName (builtins.elemAt segments 1)
    else
      false;

  declaredRequirements = lib.concatMap (
    workloadName:
    lib.mapAttrsToList (name: declaration: {
      owner = workloadId workloadName;
      inherit workloadName name declaration;
    }) (requirementsOf workloadName)
  ) workloadNames;
  requirementsForDeclaration =
    requirement:
    let
      inherit (requirement)
        owner
        workloadName
        name
        declaration
        ;
      rawTarget =
        if !builtins.isAttrs declaration then
          throw "topology: requirement owner='${owner}' name='${name}' target='<invalid>' declaration must be an attrset"
        else if !builtins.hasAttr "target" declaration then
          throw "topology: requirement owner='${owner}' name='${name}' target='<unset>' is missing target"
        else
          declaration.target;
      targetLabel =
        if builtins.isNull rawTarget then
          "<placement>"
        else if builtins.isString rawTarget then
          rawTarget
        else
          "<invalid>";
      failure =
        message: "topology: requirement owner='${owner}' name='${name}' target='${targetLabel}' ${message}";
      field =
        fieldName:
        if builtins.hasAttr fieldName declaration then
          declaration.${fieldName}
        else
          throw (failure "is missing '${fieldName}'");
      capability = field "capability";
      relationship = field "relationship";
      constraints = field "constraints";
      unexpectedKeys =
        if builtins.isAttrs declaration then
          unsupportedKeys [
            "capability"
            "relationship"
            "target"
            "constraints"
          ] declaration
        else
          [ ];
      targets =
        if builtins.isNull rawTarget then
          map hostId (workloadHosts.${workloadName} or [ ])
        else
          [ rawTarget ];
      mkRequirement = target: {
        id = requirementId {
          inherit
            owner
            name
            target
            capability
            relationship
            constraints
            ;
        };
        inherit
          owner
          name
          capability
          relationship
          target
          constraints
          ;
      };
    in
    assert lib.assertMsg (isStableName name) (failure "has an invalid requirement name");
    assert lib.assertMsg (unexpectedKeys == [ ]) (
      failure "has unsupported fields ${builtins.toJSON unexpectedKeys}"
    );
    assert lib.assertMsg (builtins.isNull rawTarget || builtins.isString rawTarget) (
      failure "has an invalid target"
    );
    assert lib.assertMsg (isTypedName "nori.capabilities." capability) (
      failure "has an invalid capability"
    );
    assert lib.assertMsg (isTypedName "nori.relationships." relationship) (
      failure "has an invalid relationship"
    );
    assert lib.assertMsg (builtins.isAttrs constraints) (failure "has non-attrset constraints");
    if targets == [ ] then
      throw "topology: requirement owner='${owner}' name='${name}' target='<none>' has no selected placement host"
    else
      map mkRequirement targets;
  requirements = sortById (lib.concatMap requirementsForDeclaration declaredRequirements);

  workloadRelationships = lib.concatMap (
    workloadName:
    map (
      hostName:
      mkRelationship {
        type = "nori.relationships.HostedOn";
        source = workloadId workloadName;
        target = hostId hostName;
      }
    ) (workloadHosts.${workloadName} or [ ])
  ) workloadNames;
  endpointRelationships = lib.concatMap (
    workloadName:
    lib.mapAttrsToList (
      endpointName: _endpoint:
      mkRelationship {
        type = "nori.relationships.ProvidedBy";
        source = endpointId workloadName endpointName;
        target = workloadId workloadName;
      }
    ) (resolvedEndpointsFor workloadName)
  ) workloadNames;
  diskRelationships = lib.mapAttrsToList (
    diskName: disk:
    mkRelationship {
      type = "nori.relationships.AttachedTo";
      source = deviceId diskName;
      target = hostId disk.attachedHost;
    }
  ) disks;
  datasetRelationships = lib.concatMap (
    datasetName:
    let
      dataset = datasets.${datasetName};
    in
    map (
      workloadName:
      mkRelationship {
        type = "nori.relationships.Writes";
        source = workloadId workloadName;
        target = datasetId datasetName;
      }
    ) (dataset.producers or [ ])
    ++ map (
      workloadName:
      mkRelationship {
        type = "nori.relationships.Reads";
        source = workloadId workloadName;
        target = datasetId datasetName;
      }
    ) (dataset.consumers or [ ])
  ) datasetNames;
  requirementRelationships = map (
    requirement:
    mkRelationship {
      type = requirement.relationship;
      source = requirement.owner;
      inherit (requirement) target;
      requirementName = requirement.name;
    }
  ) requirements;
  relationshipRecords =
    workloadRelationships
    ++ endpointRelationships
    ++ diskRelationships
    ++ datasetRelationships
    ++ requirementRelationships;
  relationships = map (relationship: removeAttrs relationship [ "requirementName" ]) (
    sortById relationshipRecords
  );

  requirementFailure =
    requirement: message:
    "owner='${requirement.owner}' name='${requirement.name}' target='${requirement.target}' ${message}";
  constraintShapeFailures = lib.concatMap (
    requirement:
    let
      capabilitySchema = capabilityPropertySchemas.${requirement.capability} or { };
    in
    lib.concatMap (
      property:
      let
        operatorSet = requirement.constraints.${property};
      in
      if !builtins.hasAttr property capabilitySchema then
        [ (requirementFailure requirement "constrains unsupported capability property '${property}'") ]
      else if !builtins.isAttrs operatorSet then
        [ (requirementFailure requirement "constraint '${property}' must declare exactly one operator") ]
      else
        let
          operators = lib.attrNames operatorSet;
          expectedType = capabilitySchema.${property};
        in
        if lib.length operators != 1 then
          [ (requirementFailure requirement "constraint '${property}' must declare exactly one operator") ]
        else
          let
            operator = builtins.head operators;
            value = operatorSet.${operator};
          in
          if
            !lib.elem operator [
              "equal"
              "atLeast"
              "oneOf"
            ]
          then
            [ (requirementFailure requirement "constraint '${property}' uses unknown operator '${operator}'") ]
          else if operator == "equal" && jsonScalarType value != expectedType then
            [ (requirementFailure requirement "constraint '${property}.equal' must be ${expectedType}") ]
          else if operator == "atLeast" && (expectedType != "integer" || !builtins.isInt value) then
            [
              (requirementFailure requirement "constraint '${property}.atLeast' requires an integer property and value")
            ]
          else if
            operator == "oneOf"
            && (
              !builtins.isList value
              || lib.length value == 0
              || !lib.all (candidate: jsonScalarType candidate == expectedType) value
            )
          then
            [
              (requirementFailure requirement "constraint '${property}.oneOf' must be a non-empty list of ${expectedType} values")
            ]
          else
            [ ]
    ) (lib.attrNames requirement.constraints)
  ) requirements;
  constraintFailures = lib.concatMap (
    requirement:
    let
      capability = nodeIndex.${requirement.target}.capabilities.${requirement.capability};
    in
    lib.concatMap (
      property:
      let
        operatorSet = requirement.constraints.${property};
        operator = builtins.head (lib.attrNames operatorSet);
        expected = operatorSet.${operator};
      in
      if !builtins.hasAttr property capability then
        [
          (requirementFailure requirement "failed constraint '${property}.${operator}': capability property is missing")
        ]
      else
        let
          actual = capability.${property};
        in
        if operator == "equal" && actual != expected then
          [
            (requirementFailure requirement "failed constraint '${property}.equal': provider value ${builtins.toJSON actual} does not equal ${builtins.toJSON expected}")
          ]
        else if operator == "atLeast" && !builtins.isInt actual then
          [
            (requirementFailure requirement "failed constraint '${property}.atLeast': provider value must be an integer")
          ]
        else if operator == "atLeast" && actual < expected then
          [
            (requirementFailure requirement "failed constraint '${property}.atLeast': provider value ${toString actual} is below ${toString expected}")
          ]
        else if operator == "oneOf" && !lib.elem actual expected then
          [
            (requirementFailure requirement "failed constraint '${property}.oneOf': provider value ${builtins.toJSON actual} is not an allowed value")
          ]
        else
          [ ]
    ) (lib.attrNames requirement.constraints)
  ) requirements;

  invalidCapabilityDeclarations = lib.concatMap (
    node:
    let
      inherit (node) capabilities;
    in
    if !builtins.isAttrs capabilities then
      [ "node '${node.id}' capabilities must be an attrset" ]
    else
      lib.concatMap (
        capabilityName:
        let
          properties = capabilities.${capabilityName};
          propertySchema = capabilityPropertySchemas.${capabilityName} or null;
        in
        if !isTypedName "nori.capabilities." capabilityName then
          [ "node '${node.id}' has invalid capability type '${capabilityName}'" ]
        else if builtins.isNull propertySchema || capabilityName == "nori.capabilities.TopologyTarget" then
          [ "node '${node.id}' has unsupported capability type '${capabilityName}'" ]
        else if !builtins.isAttrs properties then
          [ "node '${node.id}' capability '${capabilityName}' properties must be an attrset" ]
        else
          lib.concatMap (
            property:
            if !builtins.hasAttr property propertySchema then
              [ "node '${node.id}' capability '${capabilityName}' has unsupported property '${property}'" ]
            else
              lib.optional (jsonScalarType properties.${property} != propertySchema.${property})
                "node '${node.id}' capability '${capabilityName}.${property}' must be ${propertySchema.${property}}"
          ) (lib.attrNames properties)
      ) (lib.attrNames capabilities)
  ) nodes;

  isForbiddenKey =
    name:
    let
      lowerName = lib.toLower name;
    in
    lib.any (fragment: lib.hasInfix fragment lowerName) [
      "apikey"
      "credential"
      "password"
      "privatekey"
      "runtime"
      "secret"
      "token"
    ];
  forbiddenStringFragments = [
    "/run/secrets/"
    "ENC["
    "sops.secrets"
  ];
  publicValueViolationsAt =
    path: value:
    if builtins.isPath value then
      [ "${path}: contains a Nix path" ]
    else if builtins.isFunction value then
      [ "${path}: contains a function" ]
    else if builtins.isAttrs value && lib.isDerivation value then
      [ "${path}: contains a derivation" ]
    else if builtins.isAttrs value then
      lib.concatMap (
        name:
        let
          childPath = if path == "" then name else "${path}.${name}";
        in
        lib.optional (isForbiddenKey name) "${childPath}: contains a forbidden implementation or secret-shaped key"
        ++ publicValueViolationsAt childPath value.${name}
      ) (lib.attrNames value)
    else if builtins.isList value then
      lib.concatLists (
        lib.imap0 (index: item: publicValueViolationsAt "${path}[${toString index}]" item) value
      )
    else if builtins.isString value then
      lib.concatMap (
        fragment:
        lib.optional (lib.hasInfix fragment value) "${path}: contains forbidden marker '${fragment}'"
      ) forbiddenStringFragments
    else if isJsonScalar value then
      [ ]
    else
      [ "${path}: is not JSON-safe" ];

  graph = {
    schemaVersion = 1;
    inherit nodes requirements relationships;
  };
  invalidNodeIds = lib.filter (node: !isStableNodeId node) nodes;
  duplicateNodeIds = duplicateIds nodes;
  invalidRequirementIds = lib.filter (
    requirement: requirement.id != requirementId requirement
  ) requirements;
  duplicateRequirementIds = duplicateIds requirements;
  invalidRelationshipIds = lib.filter (
    relationship:
    relationship.id != relationshipId {
      inherit (relationship)
        type
        source
        target
        requirementName
        ;
    }
  ) relationshipRecords;
  duplicateRelationshipIds = duplicateIds relationshipRecords;
  missingRequirementOwners = lib.filter (
    requirement: !builtins.hasAttr requirement.owner nodeIndex
  ) requirements;
  missingRequirementTargets = lib.filter (
    requirement: !builtins.hasAttr requirement.target nodeIndex
  ) requirements;
  invalidRelationshipEndpoints = lib.concatMap (
    relationship:
    lib.optional (
      !builtins.hasAttr relationship.source nodeIndex
    ) "relationship '${relationship.id}' source '${relationship.source}' does not exist"
    ++ lib.optional (
      !builtins.hasAttr relationship.target nodeIndex
    ) "relationship '${relationship.id}' target '${relationship.target}' does not exist"
  ) relationshipRecords;
  missingRequirementCapabilities = lib.filter (
    requirement:
    let
      target = nodeIndex.${requirement.target};
    in
    !builtins.hasAttr requirement.capability target.capabilities
  ) requirements;
  publicValueViolations = publicValueViolationsAt "topology" graph;
in
assert lib.assertMsg (invalidNodeIds == [ ]) (
  formatFailures "invalid stable node ID(s)" invalidNodeIds
);
assert lib.assertMsg (
  duplicateNodeIds == [ ]
) "topology: duplicate node ID(s): ${lib.concatStringsSep ", " duplicateNodeIds}";
assert lib.assertMsg (invalidRequirementIds == [ ]) (
  formatFailures "invalid stable requirement ID(s)" (
    map (requirement: requirement.id) invalidRequirementIds
  )
);
assert lib.assertMsg (
  duplicateRequirementIds == [ ]
) "topology: duplicate requirement ID(s): ${lib.concatStringsSep ", " duplicateRequirementIds}";
assert lib.assertMsg (invalidRelationshipIds == [ ]) (
  formatFailures "invalid stable relationship ID(s)" (
    map (relationship: relationship.id) invalidRelationshipIds
  )
);
assert lib.assertMsg (
  duplicateRelationshipIds == [ ]
) "topology: duplicate relationship ID(s): ${lib.concatStringsSep ", " duplicateRelationshipIds}";
assert lib.assertMsg (constraintShapeFailures == [ ]) (
  formatFailures "invalid requirement constraint(s)" constraintShapeFailures
);
assert lib.assertMsg (invalidCapabilityDeclarations == [ ]) (
  formatFailures "invalid capability declaration(s)" invalidCapabilityDeclarations
);
assert lib.assertMsg (missingRequirementOwners == [ ]) (
  formatFailures "requirement owner invariant failed" (
    map (
      requirement: requirementFailure requirement "failure='owner node does not exist'"
    ) missingRequirementOwners
  )
);
assert lib.assertMsg (missingRequirementTargets == [ ]) (
  formatFailures "requirement target invariant failed" (
    map (
      requirement: requirementFailure requirement "failure='target node does not exist'"
    ) missingRequirementTargets
  )
);
assert lib.assertMsg (invalidRelationshipEndpoints == [ ]) (
  formatFailures "relationship endpoint invariant failed" invalidRelationshipEndpoints
);
assert lib.assertMsg (missingRequirementCapabilities == [ ]) (
  formatFailures "requirement capability invariant failed" (
    map (
      requirement:
      requirementFailure requirement "failure='target does not provide required capability ${requirement.capability}'"
    ) missingRequirementCapabilities
  )
);
assert lib.assertMsg (constraintFailures == [ ]) (
  formatFailures "requirement constraint invariant failed" constraintFailures
);
assert lib.assertMsg (publicValueViolations == [ ]) (
  formatFailures "public topology boundary violation(s)" publicValueViolations
);
graph
