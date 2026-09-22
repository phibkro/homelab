# Restricted TOSCA 2.0 projection of the normalized intended-state graph.
#
# This function deliberately closes over no inventory files. Callers supply the
# already-normalized public graph, so evaluation cannot infer topology from
# source text or make runtime-observation claims.
topology:
let
  inherit (builtins)
    all
    attrNames
    concatMap
    deepSeq
    elem
    filter
    hasAttr
    head
    isAttrs
    isList
    isString
    length
    listToAttrs
    map
    match
    sort
    typeOf
    ;

  fail = message: throw "TOSCA projection: ${message}";

  expect = condition: message: if condition then true else fail message;

  jsonScalarType =
    value:
    let
      valueType = typeOf value;
    in
    if valueType == "string" then
      "string"
    else if valueType == "int" then
      "integer"
    else if valueType == "float" then
      "float"
    else if valueType == "bool" then
      "boolean"
    else if valueType == "null" then
      "nil"
    else
      null;

  isScalarOfType = expected: value: jsonScalarType value == expected;

  isToscaName = value: isString value && (match "^[A-Za-z][A-Za-z0-9._-]*$" value != null);

  stableName = prefix: value: "${prefix}-${builtins.hashString "sha256" value}";

  duplicate =
    values:
    let
      duplicates = filter (value: length (filter (candidate: candidate == value) values) > 1) values;
    in
    if duplicates == [ ] then null else head duplicates;

  checkUnique =
    label: values:
    let
      repeated = duplicate values;
    in
    expect (repeated == null) "${label} '${repeated}' is duplicated";

  propertyContext = context: name: "${context} property '${name}'";

  valueSchema =
    context: value:
    let
      scalarType = jsonScalarType value;
    in
    if scalarType != null then
      { type = scalarType; }
    else if isList value then
      let
        scalarTypes = map jsonScalarType value;
        entryType = if scalarTypes == [ ] then "string" else head scalarTypes;
      in
      if all (type: type != null && type == entryType) scalarTypes then
        {
          type = "list";
          entry_schema = {
            type = entryType;
          };
        }
      else
        fail "${context} has a list with unsupported mixed or structured entries"
    else if isAttrs value then
      if attrNames value == [ ] then
        {
          type = "map";
          entry_schema = {
            type = "string";
          };
        }
      else
        {
          type = stableName "nori.data" context;
        }
    else
      fail "${context} has an unsupported non-JSON property value";

  propertyDefinitions =
    context: properties:
    if !isAttrs properties then
      fail "${context} properties must be an attribute set"
    else
      listToAttrs (
        map (name: {
          inherit name;
          value = (valueSchema (propertyContext context name) properties.${name}) // {
            required = false;
          };
        }) (attrNames properties)
      );

  dataTypeDefinitions =
    context: value:
    if isAttrs value && attrNames value != [ ] then
      [
        {
          name = stableName "nori.data" context;
          value = {
            properties = propertyDefinitions context value;
          };
        }
      ]
      ++ concatMap (name: dataTypeDefinitions (propertyContext context name) value.${name}) (
        attrNames value
      )
    else
      [ ];

  schema = import ./schema.nix;
  inherit (schema) capabilityPropertySchemas relationshipTypeSegments;
  relationshipTypeNames = attrNames relationshipTypeSegments;

  nodeKindTypes = {
    machine = "nori.nodes.Machine";
    device = "nori.nodes.Device";
    workload = "nori.nodes.Workload";
    realization = "nori.nodes.Realization";
    endpoint = "nori.nodes.Endpoint";
    dataset = "nori.nodes.Dataset";
  };

  topologyCheck =
    if !isAttrs topology then
      fail "the input is not an attribute set"
    else if !(topology ? schemaVersion) || topology.schemaVersion != 2 then
      fail "schemaVersion must be 2"
    else if !(topology ? nodes) || !isList topology.nodes then
      fail "nodes must be a list"
    else if !(topology ? requirements) || !isList topology.requirements then
      fail "requirements must be a list"
    else if !(topology ? relationships) || !isList topology.relationships then
      fail "relationships must be a list"
    else
      true;

  sourceTopology = deepSeq topologyCheck topology;

  nodeCheck =
    node:
    if !isAttrs node then
      fail "a node is not an attribute set"
    else if !(node ? id) || !isString node.id then
      fail "a node has no string id"
    else if !isToscaName node.id then
      fail "node '${node.id}' has an unsupported TOSCA template name"
    else if !(node ? kind) || !isString node.kind || !hasAttr node.kind nodeKindTypes then
      fail "node '${node.id}' has an unsupported kind"
    else if !(node ? properties) || !isAttrs node.properties then
      fail "node '${node.id}' properties must be an attribute set"
    else if !(node ? capabilities) || !isAttrs node.capabilities then
      fail "node '${node.id}' capabilities must be an attribute set"
    else
      deepSeq (map (capabilityName: capabilityCheck node capabilityName) (
        attrNames node.capabilities
      )) true;

  capabilityCheck =
    node: capabilityName:
    let
      properties = node.capabilities.${capabilityName};
    in
    if
      !hasAttr capabilityName capabilityPropertySchemas
      || capabilityName == "nori.capabilities.TopologyTarget"
    then
      fail "node '${node.id}' has unsupported capability '${capabilityName}'"
    else if !isAttrs properties then
      fail "node '${node.id}' capability '${capabilityName}' properties must be an attribute set"
    else
      deepSeq (map (
        propertyName:
        if !hasAttr propertyName capabilityPropertySchemas.${capabilityName} then
          fail "node '${node.id}' capability '${capabilityName}' has unsupported property '${propertyName}'"
        else
          expect
            (isScalarOfType capabilityPropertySchemas.${capabilityName}.${propertyName}
              properties.${propertyName}
            )
            "node '${node.id}' capability '${capabilityName}' property '${propertyName}' has an unsupported value type"
      ) (attrNames properties)) true;

  nodes =
    let
      checked = deepSeq (map nodeCheck sourceTopology.nodes) sourceTopology.nodes;
      sorted = sort (left: right: left.id < right.id) checked;
    in
    deepSeq (checkUnique "node ID" (map (node: node.id) sorted)) sorted;

  nodesById = listToAttrs (
    map (node: {
      name = node.id;
      value = node;
    }) nodes
  );

  nodeById = id: if hasAttr id nodesById then nodesById.${id} else fail "node '${id}' does not exist";

  nodeTypeName = node: "nori.nodes.${node.id}";

  relationshipCheck =
    relationship:
    if !isAttrs relationship then
      fail "a relationship is not an attribute set"
    else if !(relationship ? id) || !isString relationship.id then
      fail "a relationship has no string id"
    else if
      !(relationship ? type)
      || !isString relationship.type
      || !elem relationship.type relationshipTypeNames
    then
      fail "relationship '${relationship.id}' has an unsupported type"
    else if
      !(relationship ? source) || !isString relationship.source || !hasAttr relationship.source nodesById
    then
      fail "relationship '${relationship.id}' has an unknown source"
    else if
      !(relationship ? target) || !isString relationship.target || !hasAttr relationship.target nodesById
    then
      fail "relationship '${relationship.id}' has an unknown target"
    else if
      !(relationship ? properties)
      || !isAttrs relationship.properties
      || attrNames relationship.properties != [ ]
    then
      fail "relationship '${relationship.id}' has unsupported properties"
    else
      true;

  relationships =
    let
      checked = deepSeq (map relationshipCheck sourceTopology.relationships) sourceTopology.relationships;
      sorted = sort (left: right: left.id < right.id) checked;
    in
    deepSeq (checkUnique "relationship ID" (map (relationship: relationship.id) sorted)) sorted;

  relationshipsById = listToAttrs (
    map (relationship: {
      name = relationship.id;
      value = relationship;
    }) relationships
  );

  relationshipTemplateName = relationship: stableName "relationship" relationship.id;

  requirementRelationshipId =
    requirement:
    "relationship.${
      relationshipTypeSegments.${requirement.relationship}
    }.${requirement.owner}.${requirement.target}.${requirement.name}";

  relationshipForRequirement =
    requirement:
    let
      expectedId = requirementRelationshipId requirement;
    in
    if !hasAttr expectedId relationshipsById then
      fail "requirement '${requirement.id}' has no resolved relationship '${expectedId}'"
    else
      let
        relationship = relationshipsById.${expectedId};
      in
      if
        relationship.source != requirement.owner
        || relationship.target != requirement.target
        || relationship.type != requirement.relationship
      then
        fail "relationship '${relationship.id}' does not resolve requirement '${requirement.id}'"
      else
        relationship;

  constraintClause =
    requirement: propertyName: operators:
    let
      requirementPrefix = "requirement '${requirement.id}'";
      capabilitySchema = capabilityPropertySchemas.${requirement.capability};
      operatorNames = if isAttrs operators then attrNames operators else [ ];
      operator = if operatorNames == [ ] then null else head operatorNames;
      value = if operator == null then null else operators.${operator};
      propertyReference = {
        "$get_property" = [
          "SELF"
          "CAPABILITY"
          propertyName
        ];
      };
    in
    if !isAttrs operators then
      fail "${requirementPrefix} constraint '${propertyName}' must be an attribute set"
    else if !hasAttr propertyName capabilitySchema then
      fail "${requirementPrefix} constrains unsupported capability property '${propertyName}'"
    else if length operatorNames != 1 then
      fail "${requirementPrefix} constraint '${propertyName}' must use exactly one operator"
    else if operator == "equal" then
      if isScalarOfType capabilitySchema.${propertyName} value then
        {
          "$equal" = [
            propertyReference
            value
          ];
        }
      else
        fail "${requirementPrefix} equal constraint '${propertyName}' has an unsupported value type"
    else if operator == "atLeast" then
      if capabilitySchema.${propertyName} == "integer" && jsonScalarType value == "integer" then
        {
          "$greater_or_equal" = [
            propertyReference
            value
          ];
        }
      else
        fail "${requirementPrefix} atLeast constraint '${propertyName}' must use an integer capability and value"
    else if operator == "oneOf" then
      if
        isList value
        && value != [ ]
        && all (candidate: isScalarOfType capabilitySchema.${propertyName} candidate) value
      then
        {
          "$valid_values" = [
            propertyReference
            value
          ];
        }
      else
        fail "${requirementPrefix} oneOf constraint '${propertyName}' must be a non-empty list of matching scalar values"
    else
      fail "${requirementPrefix} uses unsupported constraint operator '${operator}'";

  constraintFilter =
    requirement:
    let
      clauses = map (
        propertyName: constraintClause requirement propertyName requirement.constraints.${propertyName}
      ) (attrNames requirement.constraints);
    in
    if clauses == [ ] then
      null
    else if length clauses == 1 then
      head clauses
    else
      { "$and" = clauses; };

  requirementCheck =
    requirement:
    if !isAttrs requirement then
      fail "a requirement is not an attribute set"
    else if !(requirement ? id) || !isString requirement.id then
      fail "a requirement has no string id"
    else if
      !(requirement ? owner) || !isString requirement.owner || !hasAttr requirement.owner nodesById
    then
      fail "requirement '${requirement.id}' has an unknown owner"
    else if !(requirement ? name) || !isString requirement.name then
      fail "requirement '${requirement.id}' has no string name"
    else if
      !(requirement ? capability)
      || !isString requirement.capability
      || !hasAttr requirement.capability capabilityPropertySchemas
      || requirement.capability == "nori.capabilities.TopologyTarget"
    then
      fail "requirement '${requirement.id}' has an unsupported capability"
    else if
      !(requirement ? relationship)
      || !isString requirement.relationship
      || !elem requirement.relationship relationshipTypeNames
    then
      fail "requirement '${requirement.id}' has an unsupported relationship"
    else if
      !(requirement ? target) || !isString requirement.target || !hasAttr requirement.target nodesById
    then
      fail "requirement '${requirement.id}' has an unknown target"
    else if !(requirement ? constraints) || !isAttrs requirement.constraints then
      fail "requirement '${requirement.id}' constraints must be an attribute set"
    else
      deepSeq [ (constraintFilter requirement) (relationshipForRequirement requirement) ] true;

  requirements =
    let
      checked = deepSeq (map requirementCheck sourceTopology.requirements) sourceTopology.requirements;
      sorted = sort (left: right: left.id < right.id) checked;
    in
    deepSeq (checkUnique "requirement ID" (map (requirement: requirement.id) sorted)) sorted;

  requirementSymbol =
    requirement:
    let
      sameName = filter (
        candidate: candidate.owner == requirement.owner && candidate.name == requirement.name
      ) requirements;
    in
    if length sameName == 1 && isToscaName requirement.name then
      requirement.name
    else
      stableName "requirement" requirement.id;

  structuralRelationships =
    let
      requirementRelationshipIds = map (
        requirement: (relationshipForRequirement requirement).id
      ) requirements;
    in
    filter (relationship: !elem relationship.id requirementRelationshipIds) relationships;

  structuralRequirementSymbol = relationship: stableName "edge" relationship.id;

  requirementsForNode = node: filter (requirement: requirement.owner == node.id) requirements;

  structuralRelationshipsForNode =
    node: filter (relationship: relationship.source == node.id) structuralRelationships;

  nodeRequirementSymbols =
    node:
    (map requirementSymbol (requirementsForNode node))
    ++ (map structuralRequirementSymbol (structuralRelationshipsForNode node));

  nodeRequirementNameChecks = map (
    node: checkUnique "node '${node.id}' requirement name" (nodeRequirementSymbols node)
  ) nodes;

  capabilitySymbol = capabilityName: stableName "capability" capabilityName;

  nodeCapabilityDefinitions =
    node:
    listToAttrs (
      [
        {
          name = "topology-target";
          value = {
            type = "nori.capabilities.TopologyTarget";
          };
        }
      ]
      ++ map (capabilityName: {
        name = capabilitySymbol capabilityName;
        value = {
          type = capabilityName;
        };
      }) (attrNames node.capabilities)
    );

  nodeCapabilityAssignments =
    node:
    listToAttrs (
      map (
        capabilityName:
        let
          properties = node.capabilities.${capabilityName};
        in
        {
          name = capabilitySymbol capabilityName;
          value = if attrNames properties == [ ] then { } else { inherit properties; };
        }
      ) (attrNames node.capabilities)
    );

  requirementDefinition =
    requirement:
    let
      filterDefinition = constraintFilter requirement;
    in
    {
      name = requirementSymbol requirement;
      value = {
        metadata = {
          "nori.requirement-id" = requirement.id;
          "nori.requirement-name" = requirement.name;
        };
        capability = requirement.capability;
        node = nodeTypeName (nodeById requirement.target);
        relationship = requirement.relationship;
        count_range = [
          1
          1
        ];
      }
      // (if filterDefinition == null then { } else { node_filter = filterDefinition; });
    };

  requirementAssignment =
    requirement:
    let
      filterDefinition = constraintFilter requirement;
    in
    {
      name = requirementSymbol requirement;
      value = {
        node = requirement.target;
        capability = requirement.capability;
        relationship = relationshipTemplateName (relationshipForRequirement requirement);
        optional = false;
      }
      // (if filterDefinition == null then { } else { node_filter = filterDefinition; });
    };

  structuralRequirementDefinition = relationship: {
    name = structuralRequirementSymbol relationship;
    value = {
      metadata = {
        "nori.relationship-id" = relationship.id;
      };
      capability = "topology-target";
      node = nodeTypeName (nodeById relationship.target);
      relationship = relationship.type;
      count_range = [
        1
        1
      ];
    };
  };

  structuralRequirementAssignment = relationship: {
    name = structuralRequirementSymbol relationship;
    value = {
      node = relationship.target;
      capability = "topology-target";
      relationship = relationshipTemplateName relationship;
      optional = false;
    };
  };

  baseNodeTypes = {
    "nori.nodes.Machine" = { };
    "nori.nodes.Device" = { };
    "nori.nodes.Workload" = { };
    "nori.nodes.Realization" = { };
    "nori.nodes.Endpoint" = { };
    "nori.nodes.Dataset" = { };
  };

  staticCapabilityTypes = listToAttrs (
    map (
      capabilityName:
      let
        schema = capabilityPropertySchemas.${capabilityName};
      in
      {
        name = capabilityName;
        value =
          if schema == { } then
            { }
          else
            {
              properties = listToAttrs (
                map (propertyName: {
                  name = propertyName;
                  value = {
                    type = schema.${propertyName};
                    required = false;
                  };
                }) (attrNames schema)
              );
            };
      }
    ) (attrNames capabilityPropertySchemas)
  );

  staticRelationshipTypes = listToAttrs (
    map (relationshipType: {
      name = relationshipType;
      value = { };
    }) relationshipTypeNames
  );

  perNodeTypes = listToAttrs (
    map (
      node:
      let
        declaredRequirements =
          (map requirementDefinition (requirementsForNode node))
          ++ (map structuralRequirementDefinition (structuralRelationshipsForNode node));
      in
      {
        name = nodeTypeName node;
        value = {
          derived_from = nodeKindTypes.${node.kind};
          capabilities = nodeCapabilityDefinitions node;
        }
        // (
          if attrNames node.properties == [ ] then
            { }
          else
            {
              properties = propertyDefinitions "node '${node.id}'" node.properties;
            }
        )
        // (
          if declaredRequirements == [ ] then
            { }
          else
            {
              requirements = declaredRequirements;
            }
        );
      }
    ) nodes
  );

  nodeTemplates = listToAttrs (
    map (
      node:
      let
        assignments =
          map requirementAssignment (requirementsForNode node)
          ++ map structuralRequirementAssignment (structuralRelationshipsForNode node);
      in
      {
        name = node.id;
        value = {
          metadata = {
            "nori.node-id" = node.id;
            "nori.node-kind" = node.kind;
          };
          type = nodeTypeName node;
        }
        // (
          if attrNames node.properties == [ ] then
            { }
          else
            {
              properties = node.properties;
            }
        )
        // (
          if attrNames node.capabilities == [ ] then
            { }
          else
            {
              capabilities = nodeCapabilityAssignments node;
            }
        )
        // (
          if assignments == [ ] then
            { }
          else
            {
              requirements = assignments;
            }
        );
      }
    ) nodes
  );

  relationshipTemplates = listToAttrs (
    map (relationship: {
      name = relationshipTemplateName relationship;
      value = {
        metadata = {
          "nori.relationship-id" = relationship.id;
          "nori.source" = relationship.source;
          "nori.target" = relationship.target;
        };
        type = relationship.type;
      };
    }) relationships
  );

  dataTypes = listToAttrs (
    concatMap (
      node:
      concatMap (
        propertyName:
        dataTypeDefinitions (propertyContext "node '${node.id}'" propertyName)
          node.properties.${propertyName}
      ) (attrNames node.properties)
    ) nodes
  );

  projection = {
    tosca_definitions_version = "tosca_2_0";
    capability_types = staticCapabilityTypes;
    data_types = dataTypes;
    relationship_types = staticRelationshipTypes;
    node_types = baseNodeTypes // perNodeTypes;
    service_template = {
      metadata = {
        "nori.schema-version" = "2";
      };
      node_templates = nodeTemplates;
      relationship_templates = relationshipTemplates;
    };
  };
in
deepSeq nodeRequirementNameChecks projection
