{
  capabilityPropertySchemas = {
    "nori.capabilities.Compute" = {
      architecture = "string";
      cores = "integer";
      memoryBytes = "integer";
    };
    "nori.capabilities.GpuCompute" = {
      backend = "string";
      vendor = "string";
      vramBytes = "integer";
    };
    "nori.capabilities.PersistentStorage" = {
      class = "string";
    };
    "nori.capabilities.OidcProvider" = {
      protocol = "string";
    };
    "nori.capabilities.TopologyTarget" = { };
  };

  relationshipTypeSegments = {
    "nori.relationships.HostedOn" = "hosted-on";
    "nori.relationships.ProvidedBy" = "provided-by";
    "nori.relationships.AttachedTo" = "attached-to";
    "nori.relationships.Writes" = "writes";
    "nori.relationships.Reads" = "reads";
    "nori.relationships.Uses" = "uses";
    "nori.relationships.AuthenticatedBy" = "authenticated-by";
  };
}
