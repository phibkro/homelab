{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
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
