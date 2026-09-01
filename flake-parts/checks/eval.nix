{ inputs, ... }:

{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      checks = {
        /**
          Layer-1 eval test — `nori.lanRoutes` → blocky.customDNS
          auto-generation. Sub-second; runs at every flake check
          via the import below. Per docs/reference/testing-
          methodology.md: eval tests catch schema regressions +
          cross-module composition errors before they surface in
          the nixosTest (which is much slower).
        */
        eval-lanroute-customdns =
          let
            result = import ../../tests/eval/lanroute-customdns.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-lanroute-customdns" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Layer-1 eval test — `nori.lanRoutes.<X>.port` validates as
          16-bit unsigned (types.port). Demonstrates the
          negative-path eval pattern: assert that a BAD config
          throws, not just that a good config succeeds.
        */
        eval-lanroute-port-validation =
          let
            result = import ../../tests/eval/lanroute-port-validation.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-lanroute-port-validation" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Layer-1 eval test — cross-product invariants over
          nori.lanRoutes. Verifies module assertions in
          modules/infra/networking/default.nix actually FIRE on
          the failure modes (port collisions, runsOn ∉ nori.hosts).
          Catches regressions that drop an assertion silently.
        */
        eval-route-invariants =
          let
            result = import ../../tests/eval/route-invariants.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-route-invariants" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Layer-1 eval test — `nori.lanRoutes.<X>.monitor` →
          `services.gatus.settings.endpoints`. Pins the registry-
          to-Gatus contract so a schema regression that silently
          drops endpoints (and the operator's alerting) fails the
          check.
        */
        eval-gatus-probes =
          let
            result = import ../../tests/eval/gatus-probes.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-gatus-probes" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Phase-0 architecture migration baseline. Pins the resolved
          workload placement per host and the entry-plane route policy
          fingerprint while implementation moves from global imports to
          a pure inventory compiler + selected runtime modules.
        */
        eval-architecture-baseline =
          let
            result = import ../../tests/eval/architecture-baseline.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-architecture-baseline" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Public inventory must stay safe for deployment, status, and
          documentation consumers. Recursively rejects compiler-private
          paths, derivations, secret-shaped keys, and secret markers.
        */
        eval-inventory-public-safe =
          let
            result = import ../../tests/eval/inventory-public-safe.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-inventory-public-safe" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Workload manifests declare their allowed host roles, and the
          pure inventory compiler rejects mismatched placements.
        */
        eval-workload-role-placement =
          let
            result = import ../../tests/eval/workload-role-placement.nix {
              inherit lib;
            };
          in
          pkgs.runCommandLocal "eval-workload-role-placement" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Canonical datasets project into producer and consumer runtime
          paths without duplicating their logical storage contract.
        */
        eval-datasets =
          let
            result = import ../../tests/eval/datasets.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-datasets" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Personal products consume explicit immutable artifacts or a
          fully governed legacy host-build exception.
        */
        eval-product-artifacts =
          let
            result = import ../../tests/eval/product-artifacts.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-product-artifacts" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Deployment builds, affected-host change scopes, and activation
          order derive from the same host/profile/workload inventory.
        */
        eval-deployment =
          let
            result = import ../../tests/eval/deployment.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-deployment" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Future status and onboarding catalogs expose the minimum
          presentation policy and no internal topology.
        */
        eval-presentations =
          let
            result = import ../../tests/eval/presentations.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-presentations" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          System adapters must be selected only by explicit profiles.
        */
        eval-system-profile-adapters =
          let
            result = import ../../tests/eval/system-profile-adapters.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-system-profile-adapters" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          The desktop resource detector must measure cgroup working set rather
          than inactive file cache retained after a child process exits.
        */
        steady-state-resource-alert-working-set =
          let
            detectorScript = builtins.head inputs.self.nixosConfigurations.workstation.config.home-manager.users.nori.systemd.user.services.steady-state-resource-alert.Service.ExecStart;
          in
          import ../../tests/eval/steady-state-resource-alert.nix {
            inherit pkgs detectorScript;
          };

        /**
          Docs-fresh — committed generated artifacts must match
          what the generators would produce right now. Catches the
          drift class where a schema change lands but the docs/
          reference/*.md artifact isn't regenerated + committed.
          Each diff is byte-equal; a single byte difference fails
          the build with the diff inline.
        */
        docs-fresh =
          pkgs.runCommandLocal "docs-fresh"
            {
              nativeBuildInputs = [ pkgs.diffutils ];
            }
            ''
              fail=0
              check() {
                local name=$1 committed=$2 generated=$3
                if ! diff -q "$committed" "$generated" > /dev/null 2>&1; then
                  echo "✗ $name: committed artifact differs from generator output"
                  echo "  committed:  $committed"
                  echo "  generator:  $generated"
                  echo "  diff:"
                  diff "$committed" "$generated" | head -20 | sed 's/^/    /'
                  fail=1
                fi
              }
              check "docs-lan-route" \
                ${../../docs/generated/lan-route.md} \
                ${inputs.self.packages.${system}.docs-lan-route}
              check "docs-topology" \
                ${../../docs/generated/topology.md} \
                ${inputs.self.packages.${system}.docs-topology}
              check "docs-capabilities" \
                ${../../docs/generated/capabilities.md} \
                ${inputs.self.packages.${system}.docs-capabilities}
              check "docs-backups" \
                ${../../docs/generated/backups.md} \
                ${inputs.self.packages.${system}.docs-backups}
              check "docs-fs" \
                ${../../docs/generated/fs.md} \
                ${inputs.self.packages.${system}.docs-fs}
              check "docs-replicas" \
                ${../../docs/generated/replicas.md} \
                ${inputs.self.packages.${system}.docs-replicas}

              if [ $fail -eq 0 ]; then
                touch $out
              else
                echo
                echo "Generated docs drifted. Regenerate + commit any failures:"
                for name in lan-route topology capabilities backups fs replicas; do
                  echo "  nix build .#docs-$name -o /tmp/r && cp /tmp/r docs/generated/$name.md && chmod +w docs/generated/$name.md"
                done
                exit 1
              fi
            '';
      };
    };
}
