{ lib, ... }:

let
  compiler = import ../../inventory;
  workloadCatalog = import ../../inventory/workloads.nix { inherit lib; };

  evaluate =
    overrides:
    builtins.tryEval (
      builtins.deepSeq (compiler ({ inherit lib workloadCatalog; } // overrides)).public true
    );

  withWorkload =
    name: change:
    workloadCatalog
    // {
      ${name} = workloadCatalog.${name} // change;
    };

  valid = evaluate { };
  mismatch = evaluate {
    workloadCatalog = withWorkload "jellyfin" { hostRoles = [ "appliance" ]; };
  };
  missing = evaluate {
    workloadCatalog = workloadCatalog // {
      jellyfin = removeAttrs workloadCatalog.jellyfin [ "hostRoles" ];
    };
  };
  unknown = evaluate {
    workloadCatalog = withWorkload "jellyfin" { hostRoles = [ "spaceship" ]; };
  };
in
assert valid.success;
assert !mismatch.success;
assert !missing.success;
assert !unknown.success;
"ok — workload manifests declare typed host roles and mismatched placements fail during inventory evaluation"
