{ lib, ... }:
let
  compiler = import ../../inventory;

  profiles = {
    base = {
      description = "test base";
      systemModules = [ ];
    };
    entry-plane = {
      description = "test entry plane";
      systemModules = [ ];
    };
  };

  identity = role: name: {
    tailnetIp = "100.64.0.1";
    lanIp = null;
    inherit role;
    roleOneLiner = "test ${role}";
    codename = name;
    hardware = "test hardware";
    primaryJob = "test placement";
  };

  nixHost = name: tags: {
    kind = "nixos";
    managementRoot = "infra/${name}";
    additionalSourceRoots = [ ];
    systemModule = ../../infra/workstation;
    homeModule = ../../users/nori/home.nix;
    profiles = [ "base" ];
    inherit tags;
    identity = identity "workhorse" name;
    capabilities = { };
  };

  hosts = {
    alpha = nixHost "alpha" [
      "nas"
      "primary"
    ];
    beta = nixHost "beta" [
      "cold"
      "nixos"
    ];
    edge = {
      kind = "ansible";
      managementRoot = "infra/edge";
      additionalSourceRoots = [ ];
      profiles = [ "entry-plane" ];
      tags = [ "entry-plane" ];
      deployment = {
        planCommand = "plan edge";
        applyCommand = "apply edge";
        verifyCommand = "verify edge";
      };
      identity = identity "appliance" "edge";
      capabilities = { };
    };
  };

  singletonPlacement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "primary" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };

  workload = {
    active = true;
    kind = "service";
    hostRoles = [ "workhorse" ];
    tags = [ ];
    placement = singletonPlacement;
    endpoints.api = {
      port = 8080;
      audience = "operator";
      exposeOnTailnet = true;
      reachability = "internal";
      noAuthReason = "test fixture";
    };
  };

  fixture = {
    inherit lib hosts profiles;
    workloadCatalog.app = workload;
    datasets = { };
    disks = { };
    site = {
      domain = "example.test";
      deprecatedDomains = [ ];
      entryPlaneHost = "edge";
    };
    backup = { };
  };

  compile = change: compiler (fixture // change);
  evaluate = change: builtins.tryEval (builtins.deepSeq (compile change).public true);
  withPlacement = placement: {
    workloadCatalog.app = workload // {
      inherit placement;
    };
  };

  baseline = (compile { }).public;
  orderedFallback =
    (compile (withPlacement {
      strategy = "first-unique";
      selectors = [
        {
          tags = [
            "cold"
            "nas"
          ];
        }
        { host = "alpha"; }
      ];
      cardinality = {
        min = 1;
        max = 1;
      };
    })).public;
  allWorkhorses =
    (compile {
      workloadCatalog.app = workload // {
        endpoints = { };
        placement = {
          strategy = "all-matches";
          selectors = [ { roles = [ "workhorse" ]; } ];
          cardinality = {
            min = 2;
            max = 2;
          };
        };
      };
    }).public;

  missingPlacement = evaluate {
    workloadCatalog.app = removeAttrs workload [ "placement" ];
  };
  unknownSelectorField = evaluate (withPlacement {
    strategy = "first-unique";
    selectors = [ { label = "primary"; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  });
  multipleSelectorKinds = evaluate (withPlacement {
    strategy = "first-unique";
    selectors = [
      {
        host = "alpha";
        tags = [ "primary" ];
      }
    ];
    cardinality = {
      min = 1;
      max = 1;
    };
  });
  unknownHost = evaluate (withPlacement {
    strategy = "first-unique";
    selectors = [ { host = "missing"; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  });
  unknownTag = evaluate (withPlacement {
    strategy = "first-unique";
    selectors = [ { tags = [ "missing" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  });
  unknownRole = evaluate (withPlacement {
    strategy = "first-unique";
    selectors = [ { roles = [ "spaceship" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  });
  ambiguousFirstUnique = evaluate (withPlacement {
    strategy = "first-unique";
    selectors = [ { roles = [ "workhorse" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  });
  invalidCardinality = evaluate (withPlacement {
    strategy = "all-matches";
    selectors = [ { roles = [ "workhorse" ]; } ];
    cardinality = {
      min = 3;
      max = 2;
    };
  });
  unboundedCardinality = evaluate (withPlacement {
    strategy = "all-matches";
    selectors = [ { roles = [ "workhorse" ]; } ];
    cardinality = {
      min = 1;
      max = null;
    };
  });
  endpointWithManyRealizations = evaluate (withPlacement {
    strategy = "all-matches";
    selectors = [ { roles = [ "workhorse" ]; } ];
    cardinality = {
      min = 2;
      max = 2;
    };
  });
  endpointOwnedPlacement = evaluate {
    workloadCatalog.app = workload // {
      endpoints.api = workload.endpoints.api // {
        runsOn = "alpha";
      };
    };
  };
  hostOwnedPlacement = evaluate {
    hosts = hosts // {
      alpha = hosts.alpha // {
        workloads = [ "app" ];
      };
    };
  };
  profileOwnedPlacement = evaluate {
    profiles = profiles // {
      base = profiles.base // {
        workloads = [ "app" ];
      };
    };
  };
  roleViolation = evaluate {
    workloadCatalog.app = workload // {
      placement = {
        strategy = "first-unique";
        selectors = [ { host = "edge"; } ];
        cardinality = {
          min = 1;
          max = 1;
        };
      };
    };
  };
in
assert baseline.workloads.app.hosts == [ "alpha" ];
assert baseline.workloads.app.endpoints.api.runsOn == "alpha";
assert
  baseline.workloads.app.realizations == [
    {
      id = "realization.app.primary";
      host = "alpha";
      instance = "primary";
    }
  ];
assert orderedFallback.workloads.app.hosts == [ "alpha" ];
assert
  allWorkhorses.workloads.app.hosts == [
    "alpha"
    "beta"
  ];
assert
  allWorkhorses.workloads.app.realizations == [
    {
      id = "realization.app.alpha";
      host = "alpha";
      instance = "alpha";
    }
    {
      id = "realization.app.beta";
      host = "beta";
      instance = "beta";
    }
  ];
assert !missingPlacement.success;
assert !unknownSelectorField.success;
assert !multipleSelectorKinds.success;
assert !unknownHost.success;
assert !unknownTag.success;
assert !unknownRole.success;
assert !ambiguousFirstUnique.success;
assert !invalidCardinality.success;
assert !unboundedCardinality.success;
assert !endpointWithManyRealizations.success;
assert !endpointOwnedPlacement.success;
assert !hostOwnedPlacement.success;
assert !profileOwnedPlacement.success;
assert !roleViolation.success;
"ok — ordered selectors resolve deterministically and malformed, ambiguous, cardinality, and role violations fail"
