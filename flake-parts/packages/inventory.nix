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
          pkgs.jq
        ];
        text = ''
          export HOMELAB_DEPLOYMENT_INDEX=${deploymentIndex}
          exec ${pkgs.bash}/bin/bash ${../../scripts/deployment-plan.sh} "$@"
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
              pkgs.jq
              pkgs.shellcheck
            ];
          }
          ''
            shellcheck ${../../scripts/deployment-plan.sh}

            export HOME="$TMPDIR/home"
            mkdir -p "$HOME" repo/modules/services/filmder
            cd repo
            git init --quiet
            git config user.name test
            git config user.email test@example.invalid
            echo baseline > modules/services/filmder/runtime.nix
            git add .
            git commit --quiet -m baseline
            echo changed >> modules/services/filmder/runtime.nix

            HOMELAB_DEPLOYMENT_INDEX=${deploymentIndex} \
              bash ${../../scripts/deployment-plan.sh} --changed-since HEAD > changed.json
            jq -e '.hosts == ["workstation"] and .activationOrder == ["workstation"]' changed.json

            # Selection unions --host with --workload, and activationOrder is
            # derived from that set. The converged workstation is the only
            # NixOS target, so both selectors resolve to the same host and
            # activation order.
            HOMELAB_DEPLOYMENT_INDEX=${deploymentIndex} \
              bash ${../../scripts/deployment-plan.sh} \
                --host workstation --workload jellyfin > selected.json
            jq -e \
              '.hosts == ["workstation"] and .activationOrder == ["workstation"]' \
              selected.json

            touch "$out"
          '';
      checks.status-components-fresh =
        pkgs.runCommandLocal "status-components-fresh"
          {
            nativeBuildInputs = [ pkgs.diffutils ];
          }
          ''
            diff -u ${../../products/status/generated/components.json} ${statusCatalog}
            touch "$out"
          '';
    };
}
