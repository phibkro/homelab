let
  active = true;
in
{
  inherit active;
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "primary-service-host" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ./nixos.nix;
  tags = [
    "gpu-bound"
    "stateful"
  ];

  topology.requires.accelerator = {
    capability = "nori.capabilities.GpuCompute";
    relationship = "nori.relationships.Uses";
    target = null;
    constraints = {
      backend.equal = "cuda";
      vramBytes.atLeast = 8589934592;
    };
  };

  endpoints =
    if active then
      {
        ai = {
          port = 11434;
          exposeOnTailnet = true;
          monitor.path = "/api/tags";
        };
      }
    else
      { };
}
