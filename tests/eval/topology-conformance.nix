{ inputs, lib, ... }:
let
  compiler = import ../../inventory/topology.nix { inherit lib; };
  validFixture = {
    hosts.workstation = {
      kind = "nixos";
      identity = {
        tailnetIp = "100.81.5.122";
        lanIp = "192.168.1.181";
        role = "workhorse";
        roleOneLiner = "test host";
        codename = "test";
        hardware = "test hardware";
        primaryJob = "test topology";
      };
      capabilities = {
        "nori.capabilities.Compute" = {
          architecture = "x86_64";
          cores = 16;
          memoryBytes = 68719476736;
        };
        "nori.capabilities.GpuCompute" = {
          backend = "cuda";
          vendor = "nvidia";
          vramBytes = 17179869184;
        };
      };
    };
    workloadCatalog.ollama = {
      kind = "service";
      hostRoles = [ "workhorse" ];
      tags = [ ];
      topology.requires.accelerator = {
        capability = "nori.capabilities.GpuCompute";
        relationship = "nori.relationships.Uses";
        target = null;
        constraints = {
          backend.equal = "cuda";
          vendor.oneOf = [ "nvidia" ];
          vramBytes.atLeast = 8589934592;
        };
      };
    };
    datasets = { };
    disks = { };
    workloadHosts.ollama = [ "workstation" ];
    resolvedEndpointsFor = _: { };
  };
  evaluate = fixture: builtins.tryEval (builtins.deepSeq (compiler fixture) true);
  workloadWithRequirement =
    change:
    validFixture.workloadCatalog.ollama
    // {
      topology = validFixture.workloadCatalog.ollama.topology // {
        requires = validFixture.workloadCatalog.ollama.topology.requires // {
          accelerator = validFixture.workloadCatalog.ollama.topology.requires.accelerator // change;
        };
      };
    };
  withWorkload = workload: validFixture // { workloadCatalog.ollama = workload; };

  production = builtins.tryEval (builtins.deepSeq inputs.self.lib.noriInventory.topology true);
  validBaseline = evaluate validFixture;
  unknownTarget = evaluate (
    withWorkload (workloadWithRequirement {
      target = "host.unknown";
    })
  );
  missingCapability = evaluate (
    validFixture
    // {
      hosts.workstation = validFixture.hosts.workstation // {
        capabilities = removeAttrs validFixture.hosts.workstation.capabilities [
          "nori.capabilities.GpuCompute"
        ];
      };
    }
  );
  failedNumericConstraint = evaluate (
    validFixture
    // {
      hosts.workstation = validFixture.hosts.workstation // {
        capabilities = validFixture.hosts.workstation.capabilities // {
          "nori.capabilities.GpuCompute" =
            validFixture.hosts.workstation.capabilities."nori.capabilities.GpuCompute"
            // {
              vramBytes = 4294967296;
            };
        };
      };
    }
  );
  unknownRequirementField = evaluate (
    withWorkload (workloadWithRequirement {
      placementPolicy = "best-fit";
    })
  );
  unknownCapabilityProperty = evaluate (
    validFixture
    // {
      hosts.workstation = validFixture.hosts.workstation // {
        capabilities = validFixture.hosts.workstation.capabilities // {
          "nori.capabilities.GpuCompute" =
            validFixture.hosts.workstation.capabilities."nori.capabilities.GpuCompute"
            // {
              device = "gpu0";
            };
        };
      };
    }
  );
  mistypedConstraintValue = evaluate (
    withWorkload (workloadWithRequirement {
      constraints.vendor.oneOf = [
        "nvidia"
        1
      ];
    })
  );
  unknownTopologyField = evaluate (
    withWorkload (
      validFixture.workloadCatalog.ollama
      // {
        topology = validFixture.workloadCatalog.ollama.topology // {
          require = validFixture.workloadCatalog.ollama.topology.requires;
        };
      }
    )
  );
  reservedCapability = evaluate (
    validFixture
    // {
      hosts.workstation = validFixture.hosts.workstation // {
        capabilities = validFixture.hosts.workstation.capabilities // {
          "nori.capabilities.TopologyTarget" = { };
        };
      };
    }
  );
  unsupportedEndpointRequirement = evaluate (
    validFixture
    // {
      resolvedEndpointsFor = _: {
        api.topology.requires.accelerator =
          validFixture.workloadCatalog.ollama.topology.requires.accelerator;
      };
    }
  );
in
assert production.success;
assert validBaseline.success;
assert !unknownTarget.success;
assert !missingCapability.success;
assert !failedNumericConstraint.success;
assert !unknownRequirementField.success;
assert !unknownCapabilityProperty.success;
assert !mistypedConstraintValue.success;
assert !unknownTopologyField.success;
assert !reservedCapability.success;
assert !unsupportedEndpointRequirement.success;
"ok — topology compiler accepts the production graph and rejects malformed targets, capabilities, constraints, and declaration fields"
