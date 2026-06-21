/*
  Generated reference for the `nori.replicas` schema (cross-host
  dataset replication metadata). Pairs with `docs/reference/storage.md`.

  Build:      nix build .#docs-replicas
  Committed:  docs/generated/replicas.md
*/
{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    let
      eval = inputs.self.nixosConfigurations.workstation;
      helpers = import ../../lib/nixdoc.nix { inherit pkgs lib eval; };
    in
    {
      packages.docs-replicas = helpers.mkSimpleDocsArtifact {
        name = "replicas";
        moduleFile = ../../modules/infra/storage/replication.nix;
        category = "replicas";
      };
    };
}
