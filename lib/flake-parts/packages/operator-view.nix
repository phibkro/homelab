{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      inventory = inputs.self.lib.noriInventory;
      deployment = inputs.self.lib.noriDeployment;
      recoveryEvidence = inputs.self.lib.noriRecoveryEvidence;
      nixosConfigurations = inputs.self.nixosConfigurations;

      activeServices = lib.filterAttrs (
        _: workload: workload.active && workload.kind == "service"
      ) inventory.workloads;

      nixosBackupEntries = lib.concatMap (
        hostName:
        let
          hostConfig = nixosConfigurations.${hostName}.config;
          defaultTargets = lib.attrNames hostConfig.nori.backupTargets;
        in
        lib.mapAttrsToList (
          jobName: job:
          let
            configured = job.include != null;
            targets = if job.targets == null then defaultTargets else job.targets;
            active = configured && hostConfig.nori.backupDelivery.enable && targets != [ ];
            state =
              if !configured then
                "skipped"
              else if active then
                "active"
              else
                "disabled";
            reason =
              if job.skip != null then
                job.skip
              else if !hostConfig.nori.backupDelivery.enable then
                "backup delivery disabled"
              else if targets == [ ] then
                "no backup targets"
              else
                null;
          in
          {
            host = hostName;
            name = jobName;
            inherit (job) workload;
            inherit state reason targets;
            observationUnits = lib.optionals active (
              map (target: "restic-backups-${jobName}-${target}.service") targets
            );
            observationSource = "systemd-unit";
          }
        ) hostConfig.nori.backups
      ) (lib.attrNames nixosConfigurations);

      piBackupEntries = map (
        job:
        let
          active = inventory.backup.enabled;
        in
        {
          host = "pi";
          inherit (job) name workload;
          state = if active then "active" else "disabled";
          reason = if active then null else "Pi backup delivery disabled";
          targets = [ inventory.backup.targetName ];
          observationUnits = lib.optionals active [ "pi-restic-freshness.service" ];
          observationSource = "repository-freshness-check";
        }
      ) inventory.backup.pi.jobs;

      backupEntries = nixosBackupEntries ++ piBackupEntries;
      invalidBackupWorkloadMappings = map (backup: "${backup.host}/${backup.name}->${backup.workload}") (
        lib.filter (
          backup:
          backup.workload != null
          && (
            !(builtins.hasAttr backup.workload activeServices)
            || !(lib.elem backup.host activeServices.${backup.workload}.hosts)
          )
        ) backupEntries
      );

      routesFor =
        workloadName:
        lib.mapAttrsToList (routeName: route: {
          id = routeName;
          inherit (route)
            hostname
            host
            audience
            authentication
            reachability
            ;
          url = "https://${route.hostname}";
          probe = route.monitorProbeName;
        }) (lib.filterAttrs (_: route: route.workload == workloadName) inventory.routes);

      evidenceFor =
        workloadName:
        lib.mapAttrsToList (id: evidence: {
          inherit id;
          inherit (evidence) scope report gates;
          model = evidence.model or null;
        }) (lib.filterAttrs (_: evidence: (evidence.workload or null) == workloadName) recoveryEvidence);

      backupsFor =
        workloadName: workload:
        let
          recovery = workload.recovery or null;
          recoveryJob = if recovery == null then null else recovery.backupJob;
        in
        lib.filter (
          backup:
          let
            assignedWorkload = backup.workload or null;
          in
          lib.elem backup.host workload.hosts
          && (
            if assignedWorkload != null then
              assignedWorkload == workloadName
            else
              backup.name == workloadName || (recoveryJob != null && backup.name == recoveryJob)
          )
        ) backupEntries;

      serviceRows = lib.mapAttrsToList (
        id: workload:
        let
          routes = routesFor id;
          recovery = workload.recovery or null;
        in
        {
          inherit id;
          declared = {
            inherit (workload) hosts;
            deploymentOwners = map (host: deployment.targets.${host}.kind) workload.hosts;
            inherit routes;
            probes = lib.unique (
              (lib.filter (probe: probe != null) (map (route: route.probe) routes)) ++ workload.probeNames
            );
            backups = backupsFor id workload;
            recovery =
              if recovery == null then
                null
              else
                {
                  inherit (recovery) model backupJob;
                };
          };
          proven.recoveryEvidence = evidenceFor id;
        }
      ) activeServices;

      declaration =
        assert lib.assertMsg (invalidBackupWorkloadMappings == [ ])
          "operator-view: backup workload mappings must name a co-located active service workload: ${lib.concatStringsSep ", " invalidBackupWorkloadMappings}";
        {
          schemaVersion = 1;
          healthSource = {
            kind = "victoriametrics";
            url = if inventory.routes ? tsdb then "https://${inventory.routes.tsdb.hostname}" else null;
            metric = "gatus_results_endpoint_success";
            maxAgeSeconds = 300;
          };
          services = serviceRows;
        };

      declarationJson = (pkgs.formats.json { }).generate "operator-view-declaration.json" declaration;

      operatorView = pkgs.writeShellApplication {
        name = "operator-view";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          jq
          inetutils
          openssh
          systemd
          util-linux
        ];
        text = ''
          export OPERATOR_VIEW_DECLARATION=${lib.escapeShellArg (toString declarationJson)}
          ${builtins.readFile ../../../scripts/operator-view.sh}
        '';
      };
    in
    {
      packages = {
        operator-view = operatorView;
        operator-view-data = declarationJson;
      };

      checks.operator-view =
        pkgs.runCommand "operator-view-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              curl
              jq
              inetutils
              openssh
              systemd
              util-linux
            ];
          }
          ''
            jq -e '
              .schemaVersion == 1 and
              ([.services[].id] | length == (unique | length)) and
              ([.services[] | select(.declared.hosts | length == 0)] | length == 0) and
              .healthSource.maxAgeSeconds == 300 and
              ([.services[] | select(.id == "jellyfin")][0] |
                .declared.routes[0].authentication == "service-native-or-exception" and
                .declared.probes == ["external-media"] and
                .declared.backups[0].name == "jellyfin") and
              ([.services[] | select(.id == "pihole")][0] |
                .declared.deploymentOwners == ["ansible"] and
                .declared.probes == ["pihole-admin", "pihole-dns-answer"] and
                .declared.backups[0].observationSource == "repository-freshness-check" and
                .proven.recoveryEvidence[0].report != null) and
              ([.services[] | select(.id == "caddy")][0] |
                .declared.routes == [] and
                .declared.backups[0].name == "caddy")
            ' ${declarationJson} >/dev/null
            mkdir fake-bin
            cat >fake-bin/curl <<'EOF'
            #!${pkgs.bash}/bin/bash
            cat "$OPERATOR_VIEW_TEST_HEALTH"
            EOF
            chmod +x fake-bin/curl
            cat >fake-bin/systemctl <<'EOF'
            #!${pkgs.bash}/bin/bash
            printf 'Result=success\nInactiveExitTimestamp=@%s\n' "$OPERATOR_VIEW_TEST_FUTURE_BACKUP"
            EOF
            chmod +x fake-bin/systemctl


            now=$(date +%s)
            jq -n \
              --arg url "https://fixture.invalid" \
              --arg host "$(hostname --short)" \
              '{
                schemaVersion: 1,
                healthSource: {
                  kind: "victoriametrics",
                  url: $url,
                  metric: "gatus_results_endpoint_success",
                  maxAgeSeconds: 300
                },
                services: [
                  {
                    id: "stale",
                    declared: {
                      hosts: ["fixture"],
                      deploymentOwners: ["nixos"],
                      routes: [],
                      probes: ["stale"],
                      backups: [{
                        host: "fixture",
                        name: "disabled",
                        workload: "stale",
                        state: "disabled",
                        reason: "backup delivery disabled",
                        targets: ["fixture"],
                        observationUnits: [],
                        observationSource: "systemd-unit"
                      }],
                      recovery: null
                    },
                    proven: {recoveryEvidence: []}
                  },
                  {
                    id: "future",
                    declared: {
                      hosts: ["fixture"],
                      deploymentOwners: ["nixos"],
                      routes: [],
                      probes: ["future"],
                      backups: [],
                      recovery: null
                    },
                    proven: {recoveryEvidence: []}
                  },
                  {
                    id: "future-backup",
                    declared: {
                      hosts: [$host],
                      deploymentOwners: ["nixos"],
                      routes: [],
                      probes: [],
                      backups: [{
                        host: $host,
                        name: "future-backup",
                        workload: "future-backup",
                        state: "active",
                        reason: null,
                        targets: ["fixture"],
                        observationUnits: ["fixture.service"],
                        observationSource: "systemd-unit"
                      }],
                      recovery: null
                    },
                    proven: {recoveryEvidence: []}
                  }
                ]
              }' >fixture-declaration.json
            jq -n \
              --argjson stale "$((now - 301))" \
              --argjson future "$((now + 60))" \
              '{
                status: "success",
                data: {
                  result: [
                    {metric: {key: "_stale"}, value: [$stale, "1"]},
                    {metric: {key: "_future"}, value: [$future, "1"]}
                  ]
                }
              }' >health.json
            PATH="$PWD/fake-bin:$PATH" \
              OPERATOR_VIEW_TEST_HEALTH="$PWD/health.json" \
              OPERATOR_VIEW_TEST_FUTURE_BACKUP="$((now + 60))" \
              OPERATOR_VIEW_DECLARATION="$PWD/fixture-declaration.json" \
              bash ${../../../scripts/operator-view.sh} --json >fixture-output.json
            jq -e '
              .sources.health.status == "ok" and
              ([.services[] | select(.id == "stale")][0] |
                .observed.health.state == "unknown" and
                .observed.health.reason == "stale" and
                .observed.backup.state == "not-active") and
              ([.services[] | select(.id == "future")][0] |
                .observed.health.state == "unknown" and
                .observed.health.reason == "future" and
                .observed.backup.state == "not-declared") and
              ([.services[] | select(.id == "future-backup")][0] |
                .observed.health.state == "unmonitored" and
                .observed.backup.state == "unknown" and
                .observed.backup.ageSeconds == null and
                .observed.backup.jobs[0].observations[0].error == "future completion timestamp")
            ' fixture-output.json >/dev/null

            jq '.data.result[0].value[0] = "1e100"' health.json >invalid-health.json
            cp fixture-declaration.json invalid-declaration.json
            PATH="$PWD/fake-bin:$PATH" \
              OPERATOR_VIEW_TEST_HEALTH="$PWD/invalid-health.json" \
              OPERATOR_VIEW_DECLARATION="$PWD/invalid-declaration.json" \
              bash ${../../../scripts/operator-view.sh} --json >invalid-output.json
            jq -e '
              .sources.health.status == "unavailable" and
              all(.services[] | select(.declared.probes | length > 0);
                .observed.health.state == "unknown")
            ' invalid-output.json >/dev/null

            jq '.healthSource.url = null' fixture-declaration.json >missing-source-declaration.json
            OPERATOR_VIEW_DECLARATION="$PWD/missing-source-declaration.json" \
              bash ${../../../scripts/operator-view.sh} --json >missing-source-output.json
            jq -e '
              .sources.health.status == "unavailable" and
              .sources.health.url == null and
              all(.services[] | select(.declared.probes | length > 0);
                .observed.health.state == "unknown")
            ' missing-source-output.json >/dev/null
            touch "$out"
          '';
    };
}
