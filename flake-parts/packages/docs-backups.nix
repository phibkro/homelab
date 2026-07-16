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
      activeJobs = lib.filterAttrs (_: cfg: cfg.include != null) eval.config.nori.backups;
      defaultTargets = lib.attrNames eval.config.nori.backupTargets;
      renderList = values: lib.concatStringsSep "<br>" (map (value: "`${value}`") values);
      renderJob =
        name: cfg:
        let
          targets = if cfg.targets == null then defaultTargets else cfg.targets;
        in
        "| `${name}` | `${cfg.tier}` | ${renderList targets} | ${renderList cfg.include} |";
      activeJobsAppendix = ''

        ## Evaluated workstation jobs

        Generated from the evaluated `nori.backups` registry. Counts and membership
        therefore change with configuration instead of being duplicated in prose.

        | Job | Tier | Effective targets | Include paths |
        |---|---|---|---|
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList renderJob activeJobs)}
      '';
    in
    {
      packages.docs-backups = helpers.mkSimpleDocsArtifact {
        name = "backups";
        moduleFile = ../../modules/infra/backup/default.nix;
        category = "backups";
        appendix = activeJobsAppendix;
      };
    };
}
