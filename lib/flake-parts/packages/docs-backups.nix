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
      hostEvals = inputs.self.nixosConfigurations;
      eval = hostEvals.workstation;
      helpers = import ../../nixdoc.nix { inherit pkgs lib eval; };
      renderList = values: lib.concatStringsSep "<br>" (map (value: "`${value}`") values);
      renderHostJobs =
        hostName:
        let
          host = hostEvals.${hostName};
          activeJobs = lib.filterAttrs (_: cfg: cfg.include != null) host.config.nori.backups;
          defaultTargets = lib.attrNames host.config.nori.backupTargets;
          renderJob =
            name: cfg:
            let
              targets = if cfg.targets == null then defaultTargets else cfg.targets;
            in
            "| `${hostName}` | `${name}` | `${cfg.tier}` | ${renderList targets} | ${renderList cfg.include} |";
        in
        lib.concatStringsSep "\n" (lib.mapAttrsToList renderJob activeJobs);
      activeJobsAppendix = ''

        ## Evaluated NixOS host jobs

        Generated from each evaluated NixOS host's `nori.backups` registry.
        Counts, membership, and placement therefore change with configuration.

        | Host | Job | Tier | Effective targets | Include paths |
        |---|---|---|---|---|
        ${lib.concatMapStringsSep "\n" renderHostJobs (lib.attrNames hostEvals)}
      '';
    in
    {
      packages.docs-backups = helpers.mkSimpleDocsArtifact {
        name = "backups";
        moduleFile = ../../../infra/common/nixos/backup.nix;
        category = "backups";
        appendix = activeJobsAppendix;
      };
    };
}
