/**
  Acquisition runtime — intentionally coupled.

  The stack shares storage and permissions, so one module owns its import
  graph. Each child still gates its own realization from the compiler's
  `currentWorkloads` projection. Disabling or moving one workload cannot start
  it through an active sibling.
*/
_:
let
  members = import ./members.nix;
in
{
  imports = [ ./resources.nix ] ++ map (member: member.nixosModule) members;
}
