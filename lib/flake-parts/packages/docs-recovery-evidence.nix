/*
  Generated recovery contracts and recorded-evidence index.

  Build:      nix build .#docs-recovery-evidence
  Output:     ./result (CommonMark file)
  Committed:  docs/generated/recovery-evidence.md
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
      inventory = inputs.self.lib.noriInventory;
      hostEvals = inputs.self.nixosConfigurations;
      evidenceRegistry = inputs.self.lib.noriRecoveryEvidence;
      inherit (inventory) workloads;
      sourceRoot = ../../..;
      renderList =
        values:
        if values == [ ] then "—" else lib.concatStringsSep "<br>" (map (value: "`${value}`") values);
      renderOptional = value: if value == null then "—" else "`${value}`";
      activeNixosJobs = lib.concatMap (
        hostName:
        let
          host = hostEvals.${hostName};
          defaultTargets = lib.attrNames host.config.nori.backupTargets;
          activeJobs = lib.filterAttrs (_: cfg: cfg.include != null) host.config.nori.backups;
        in
        lib.mapAttrsToList (name: cfg: {
          inherit hostName name;
          inherit (cfg) include exclude;
          targets = if cfg.targets == null then defaultTargets else cfg.targets;
        }) activeJobs
      ) (lib.attrNames hostEvals);
      activePiJobs = map (job: {
        hostName = "pi";
        inherit (job) name;
        include = job.paths;
        exclude = [ ];
        targets = [ inventory.backup.targetName ];
      }) inventory.backup.pi.jobs;
      allJobs = activeNixosJobs ++ activePiJobs;
      jobKey = job: "${job.hostName}:${job.name}";
      jobKeys = map jobKey allJobs;
      duplicateJobKeys = lib.filter (key: lib.count (candidate: candidate == key) jobKeys > 1) (
        lib.unique jobKeys
      );
      jobs = lib.listToAttrs (map (job: lib.nameValuePair (jobKey job) job) allJobs);
      contracts = lib.filterAttrs (_: workload: workload.active && workload ? recovery) workloads;
      evidenceIdsFor =
        workloadName:
        lib.attrNames (
          lib.filterAttrs (_: evidence: (evidence.workload or null) == workloadName) evidenceRegistry
        );
      resolveWorkload =
        workloadName: workload:
        let
          hostNames = workload.hosts;
          hostName =
            assert lib.assertMsg (
              builtins.length hostNames == 1
            ) "recovery evidence: workload '${workloadName}' must resolve to exactly one host";
            builtins.head hostNames;
          key = "${hostName}:${workload.recovery.backupJob}";
          job =
            assert lib.assertMsg (builtins.hasAttr key jobs)
              "recovery evidence: workload '${workloadName}' references missing active backup job '${key}'";
            jobs.${key};
        in
        {
          inherit workloadName hostName job;
          inherit (workload.recovery) model backupJob;
          evidenceIds = evidenceIdsFor workloadName;
        };
      resolvedWorkloads = lib.mapAttrs resolveWorkload contracts;
      contractRow =
        _name: contract:
        "| `${contract.workloadName}` | `${contract.hostName}` | `${contract.model}` | `${contract.backupJob}` | ${renderList contract.job.targets} | ${renderList contract.job.include} | ${renderList contract.job.exclude} | ${renderList contract.evidenceIds} |";
      contractRows = lib.concatStringsSep "\n" (lib.mapAttrsToList contractRow resolvedWorkloads);
      resolveEvidence =
        evidenceId: evidence:
        let
          workload = if evidence ? workload then workloads.${evidence.workload} else null;
          hostNames = if workload == null then [ evidence.host ] else workload.hosts;
          hostName =
            assert lib.assertMsg (
              builtins.length hostNames == 1
            ) "recovery evidence: '${evidenceId}' must resolve to exactly one host";
            builtins.head hostNames;
          recovery =
            if workload == null then
              {
                inherit (evidence) model backupJob;
              }
            else
              workload.recovery;
          key = "${hostName}:${recovery.backupJob}";
          job =
            assert lib.assertMsg (builtins.hasAttr key jobs)
              "recovery evidence: '${evidenceId}' references missing active backup job '${key}'";
            jobs.${key};
          reportPath = sourceRoot + "/${evidence.report}";
        in
        assert lib.assertMsg (builtins.pathExists reportPath)
          "recovery evidence: '${evidenceId}' report does not exist: ${evidence.report}";
        {
          inherit evidenceId hostName job;
          inherit (evidence)
            scope
            report
            gates
            observedAt
            maxAgeDays
            ;
          workloadName = if workload == null then null else evidence.workload;
          inherit (recovery) model backupJob;
        };
      resolvedEvidence = lib.mapAttrs resolveEvidence evidenceRegistry;
      evidenceRow =
        _name: evidence:
        let
          reportLink = "../${lib.removePrefix "docs/" evidence.report}";
        in
        "| `${evidence.evidenceId}` | `${evidence.scope}` | ${renderOptional evidence.workloadName} | `${evidence.hostName}` | `${evidence.model}` | `${evidence.backupJob}` | `${evidence.observedAt}` | `${toString evidence.maxAgeDays}` | ${renderList evidence.job.targets} | ${renderList evidence.job.include} | ${renderList evidence.job.exclude} | ${renderList evidence.gates} | [report](${reportLink}) |";
      evidenceRows = lib.concatStringsSep "\n" (lib.mapAttrsToList evidenceRow resolvedEvidence);
    in
    {
      packages.docs-recovery-evidence =
        assert lib.assertMsg (duplicateJobKeys == [ ])
          "recovery evidence: duplicate evaluated host/job keys: ${lib.concatStringsSep ", " duplicateJobKeys}";
        pkgs.writeText "recovery-evidence.md" ''
          ---
          generated: true
          source: lib/flake-parts/packages/docs-recovery-evidence.nix
          regenerate: nix build .#docs-recovery-evidence
          ---

          # Recovery contracts and evidence

          This view joins three distinct sources without treating them as the
          same claim:

          - workload manifests own service identity, placement, and recovery model;
          - evaluated backup jobs own targets, included paths, and exclusions;
          - `inventory/recovery-evidence.nix` indexes recorded dated reports.

          A configured backup is not recovery evidence. An evidence link joins
          the same subject; it does not claim that the report exercised the
          current declaration. The report's source revision controls that
          boundary. Read it for snapshot identity, results, limits, and cleanup.

          The complete evaluated job inventory remains in
          [`backups.md`](backups.md). A job omitted here has no workload recovery
          contract; omission is not a live coverage verdict.

          ## Declared workload recovery contracts

          | Workload | Host | Model | Backup job | Targets | Include paths | Exclude paths | Related evidence |
          |---|---|---|---|---|---|---|---|
          ${contractRows}

          ## Recorded recovery evidence

          Gates are historical report checkpoints, not live status or current
          configuration conformance. `Observed` and `max age` are the
          authoritative freshness inputs used by the runtime evidence-age
          monitor.

          | Evidence | Scope | Workload | Host | Model | Backup job | Observed | Max age (days) | Current targets | Current include paths | Current exclude paths | Observed gates | Report |
          |---|---|---|---|---|---|---|---|---|---|---|---|---|
          ${evidenceRows}
        '';
    };
}
