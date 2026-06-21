/*
  Generated reference for the `nori.fs` schema. Pairs with the hand-
  written `docs/reference/storage.md` for the WHY (value tiers, btrfs
  subvolume rationale); this artifact carries the WHAT (field types).

  Build:      nix build .#docs-fs
  Committed:  docs/generated/fs.md
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
      packages.docs-fs = helpers.mkSimpleDocsArtifact {
        name = "fs";
        moduleFile = ../../modules/infra/storage/default.nix;
        category = "fs";
      };
    };
}
