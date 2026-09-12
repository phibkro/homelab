{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      topologyIntent = inputs.self.lib.noriInventory.topology;
      toscaProjection = import ../../topology/tosca.nix topologyIntent;
      topologyIntentJson = pkgs.writeText "topology.intent.json" (
        builtins.toJSON topologyIntent
      );
      toscaBody = (pkgs.formats.yaml { }).generate "topology.intent.tosca.body.yaml" (
        builtins.removeAttrs toscaProjection [ "tosca_definitions_version" ]
      );
      topologyIntentTosca = pkgs.runCommand "topology.intent.tosca.yaml" { } ''
        printf '%s\n' 'tosca_definitions_version: tosca_2_0' > "$out"
        ${pkgs.coreutils}/bin/cat ${toscaBody} >> "$out"
      '';
      publicInventory = pkgs.writeText "homelab-inventory.json" (
        builtins.toJSON inputs.self.lib.noriInventory
      );
      deploymentIndex = pkgs.writeText "homelab-deployment-index.json" (
        builtins.toJSON inputs.self.lib.noriDeployment
      );
      statusCatalog = pkgs.writeText "homelab-status.json" ''
        ${builtins.toJSON inputs.self.lib.noriInventory.status}
      '';
      portalCatalog = pkgs.writeText "homelab-portal.json" (
        builtins.toJSON inputs.self.lib.noriInventory.portal
      );
      deploymentPlan = pkgs.writeShellApplication {
        name = "deployment-plan";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          export HOMELAB_DEPLOYMENT_INDEX=${deploymentIndex}
          exec ${pkgs.bash}/bin/bash ${../../../scripts/deployment-plan.sh} "$@"
        '';
      };
    in
    {
      packages.inventory-json = publicInventory;
      packages.topology-intent-json = topologyIntentJson;
      packages.topology-intent-tosca = topologyIntentTosca;
      packages.status-json = statusCatalog;
      packages.portal-json = portalCatalog;
      packages.deployment-plan = deploymentPlan;
      apps.deployment-plan = {
        type = "app";
        program = "${deploymentPlan}/bin/deployment-plan";
        meta.description = "Derive homelab build and activation plans from inventory selectors or Git changes";
      };
      checks.deployment-plan =
        pkgs.runCommandLocal "deployment-plan-test"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.git
              pkgs.gnugrep
              pkgs.coreutils
              pkgs.jq
              pkgs.shellcheck
            ];
          }
          ''
            shellcheck ${../../../scripts/deployment-plan.sh} ${../../../tests/deployment-plan_test.sh}
            bash ${../../../tests/deployment-plan_test.sh} \
              ${../../../scripts/deployment-plan.sh} ${deploymentIndex}

            touch "$out"
          '';
      checks.status-components-fresh =
        pkgs.runCommandLocal "status-components-fresh"
          {
            nativeBuildInputs = [ pkgs.diffutils ];
          }
          ''
            diff -u ${../../../products/status/generated/components.json} ${statusCatalog}
            touch "$out"
          '';
    };
}
