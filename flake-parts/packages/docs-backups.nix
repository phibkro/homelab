/*
  Generated reference for the `nori.backups` schema. The hand-written
  `docs/reference/services.md § backup` keeps the WHY + patterns; this
  artifact carries the WHAT (fields, types, defaults).

  Build:      nix build .#docs-backups
  Output:     ./result (CommonMark file)
  Committed:  docs/generated/backups.md
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
      packages.docs-backups = helpers.mkSimpleDocsArtifact {
        name = "backups";
        moduleFile = ../../modules/infra/backup/default.nix;
        category = "backups";
      };
    };
}
