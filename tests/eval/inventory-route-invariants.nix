{ lib }:

/**
  Route declarations are compiled from workload manifests before NixOS or
  Ansible adapters run. This test forces the compiler's cross-route invariants
  against deliberately invalid catalogs, then checks one production projection.
*/

let
  catalog = import ../../inventory/workloads.nix { inherit lib; };
  compile = workloadCatalog: import ../../inventory/default.nix { inherit lib workloadCatalog; };
  evaluate =
    workloadCatalog: builtins.tryEval (builtins.deepSeq (compile workloadCatalog).public.routes true);

  invalidPortCatalog = lib.recursiveUpdate catalog {
    ollama.endpoints.ai.port = 99999;
  };
  duplicatePortCatalog = lib.recursiveUpdate catalog {
    ollama.endpoints."ai-duplicate" = catalog.ollama.endpoints.ai;
  };
  duplicateNameCatalog = lib.recursiveUpdate catalog {
    ollama.endpoints.alert = catalog.ollama.endpoints.ai;
  };
  unsafeOperatorCatalog = lib.recursiveUpdate catalog {
    ollama.endpoints.ai.reachability = "internet";
  };
  internalIssuerCatalog = lib.recursiveUpdate catalog {
    immich.endpoints.photos.reachability = "internet";
  };
  conflictingAuthCatalog = lib.recursiveUpdate catalog {
    immich.endpoints.photos.forwardAuth = { };
  };
  missingActivationCatalog = catalog // {
    ollama = removeAttrs catalog.ollama [ "active" ];
  };
  nonBooleanActivationCatalog = catalog // {
    ollama = catalog.ollama // { active = "true"; };
  };

  validInventory = compile catalog;
  ai = validInventory.public.routes.ai;
  projectedAi = lib.findFirst (
    route: route.name == "ai"
  ) null validInventory.internal.piProjection.pi_routes;

  validProjection =
    ai.workload == "ollama"
    && ai.host == "workstation"
    && ai.hostname == "ai.${validInventory.public.site.domain}"
    && ai.port == 11434
    && projectedAi != null
    && projectedAi.upstream_address == validInventory.public.hosts.workstation.tailnetIp
    && projectedAi.upstream_port == ai.port;

  invalidResults = {
    invalidPort = evaluate invalidPortCatalog;
    duplicatePort = evaluate duplicatePortCatalog;
    duplicateName = evaluate duplicateNameCatalog;
    unsafeOperator = evaluate unsafeOperatorCatalog;
    internalIssuer = evaluate internalIssuerCatalog;
    conflictingAuth = evaluate conflictingAuthCatalog;
    missingActivation = evaluate missingActivationCatalog;
    nonBooleanActivation = evaluate nonBooleanActivationCatalog;
  };
  rejectedInvalidCatalogs = lib.all (result: !result.success) (lib.attrValues invalidResults);
in
if validProjection && rejectedInvalidCatalogs then
  "ok — manifest routes project to Pi and invalid route catalogs fail at compile time"
else
  throw ''
    Inventory route invariants did not behave as expected.
    valid projection: ${toString validProjection}
    invalid results: ${builtins.toJSON (lib.mapAttrs (_: result: result.success) invalidResults)}
  ''
