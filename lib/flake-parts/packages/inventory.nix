{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      topologyIntent = inputs.self.lib.noriInventory.topology;
      toscaProjection = import ../../topology/tosca.nix topologyIntent;
      topologyIntentJson = pkgs.writeText "topology.intent.json" (builtins.toJSON topologyIntent);
      toscaBody = (pkgs.formats.yaml { }).generate "topology.intent.tosca.body.yaml" (
        builtins.removeAttrs toscaProjection [ "tosca_definitions_version" ]
      );
      topologyIntentTosca = pkgs.runCommand "topology.intent.tosca.yaml" { } ''
        {
          IFS= read -r yamlVersion
          IFS= read -r documentStart
          if [ "$yamlVersion" != '%YAML 1.1' ] || [ "$documentStart" != '---' ]; then
            echo "Unexpected pkgs.formats.yaml header" >&2
            exit 1
          fi
          printf '%s\n' 'tosca_definitions_version: tosca_2_0'
          ${pkgs.coreutils}/bin/cat
        } < ${toscaBody} > "$out"
      '';
      publicInventory = pkgs.writeText "homelab-inventory.json" (
        builtins.toJSON inputs.self.lib.noriInventory
      );
      deploymentIndex = pkgs.writeText "homelab-deployment-index.json" (
        builtins.toJSON inputs.self.lib.noriDeployment
      );
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
      packages.portal-json = portalCatalog;
      packages.deployment-plan = deploymentPlan;
      apps.deployment-plan = {
        type = "app";
        program = "${deploymentPlan}/bin/deployment-plan";
        meta.description = "Derive homelab build and activation plans from inventory selectors or Git changes";
      };
      checks.topology-tosca-structure =
        pkgs.runCommandLocal "topology-tosca-structure"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.jq
              pkgs.yq-go
            ];
          }
          ''
            set -euo pipefail
            test "$(head -n 1 ${topologyIntentTosca})" = 'tosca_definitions_version: tosca_2_0'
            yq -o=json '.' ${topologyIntentTosca} |
              jq -e '
                def requirement($node; $name):
                  [.service_template.node_templates[$node].requirements[] | .[$name]?]
                  | map(select(. != null))
                  | first;
                def relation($type; $source; $target):
                  [.service_template.relationship_templates[]
                    | select(
                        .type == $type
                        and .metadata["nori.source"] == $source
                        and .metadata["nori.target"] == $target
                      )]
                  | length == 1;
                requirement("realization.ollama.primary"; "accelerator") as $accelerator
                | requirement("realization.vaultwarden.primary"; "identity") as $identity
                | requirement("realization.vaultwarden.primary"; "persistent-storage") as $storage
                | .tosca_definitions_version == "tosca_2_0"
                and (.service_template.metadata["nori.schema-version"] == "2")
                and (.service_template.node_templates[$accelerator.node].capabilities | has($accelerator.capability))
                and (.service_template.node_templates[$identity.node].capabilities | has($identity.capability))
                and (.service_template.node_templates[$storage.node].capabilities | has($storage.capability))
                and (
                  (.service_template.node_templates["realization.ollama.primary"].type) as $realizationType
                  | .node_types[$realizationType].derived_from == "nori.nodes.Realization"
                )
                and relation("nori.relationships.Realizes"; "realization.ollama.primary"; "workload.ollama")
                and relation("nori.relationships.HostedOn"; "realization.ollama.primary"; "host.workstation")
                and relation("nori.relationships.BoundTo"; "endpoint.ollama.ai"; "realization.ollama.primary")
                and (
                  (.service_template.node_templates["host.adelie"].type) as $adelieType
                  | .node_types[$adelieType].properties.lanIp.type == "nil"
                )
                and (.service_template.node_templates["host.adelie"].properties | has("lanIp"))
                and (.service_template.node_templates["host.adelie"].properties.lanIp == null)
              ' >/dev/null
            touch "$out"
          '';
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
    };
}
