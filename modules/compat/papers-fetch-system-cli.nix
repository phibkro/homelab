/**
  Compatibility adapter: expose the operator-only papers-fetch CLI as a
  system package on Aurora.

  Owner: operator user-capability composition.
  Reason: the CLI writes into Aurora's local Paperless consume directory, but
  the user-capability/profile boundary is migrated in Phase 5.
  Removal trigger: the research capability profile can project host-local CLI
  packages and its package-presence assertion replaces the Phase 3 baseline.
  Behavior proof: tests/eval/architecture-baseline.nix asserts that Aurora's
  system package set still contains `papers-fetch`.
*/
_: {
  imports = [ ../services/papers-fetch.nix ];
  nori.papersFetch.enable = true;
}
