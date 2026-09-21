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
        devenv-nixpkgs-follows-flake =
          let
            flakeLock = builtins.fromJSON (builtins.readFile ../../../flake.lock);
            devenvLock = builtins.fromJSON (builtins.readFile ../../../devenv.lock);
            flakeRevision = flakeLock.nodes.nixpkgs.locked.rev;
            devenvRevision = devenvLock.nodes.nixpkgs.locked.rev;
          in
          assert lib.assertMsg (devenvRevision == flakeRevision) ''
            devenv.lock nixpkgs (${devenvRevision}) must match flake.lock nixpkgs (${flakeRevision})
          '';
          pkgs.runCommandLocal "devenv-nixpkgs-follows-flake" { } ''
            touch $out
          '';

        eval-music-ingest =
          let
            result = import ../../../services/music-ingest/tests/eval.nix {
              inherit lib pkgs system;
              nixpkgs = inputs.nixpkgs.outPath;
            };
          in
          pkgs.runCommandLocal "eval-music-ingest" { } ''
            echo ${lib.escapeShellArg (builtins.toJSON result)} > $out
          '';

        eval-backup-enabled =
          let
            result = import ../../../tests/eval/backup-enabled.nix { inherit inputs lib; };
          in
          pkgs.runCommandLocal "eval-backup-enabled" { } ''
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
            result = import ../../../tests/eval/architecture-baseline.nix {
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
            result = import ../../../tests/eval/inventory-public-safe.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-inventory-public-safe" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Workload endpoint declarations compile into one route projection.
          Invalid ports, ownership, exposure, and authentication graphs fail
          before any NixOS or Ansible adapter can consume them.
        */
        eval-inventory-route-invariants =
          let
            result = import ../../../tests/eval/inventory-route-invariants.nix { inherit lib; };
          in
          pkgs.runCommandLocal "eval-inventory-route-invariants" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Private listener declarations, resolved endpoint hostnames, Pi
          scrape targets, and NixOS route firewall openings share the pure
          inventory compiler projection.
        */
        eval-inventory-listener-projections =
          let
            result = import ../../../tests/eval/inventory-listener-projections.nix {
              inherit inputs lib;
            };
          in
          pkgs.runCommandLocal "eval-inventory-listener-projections" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Workload manifests declare their allowed host roles, and the
          pure inventory compiler rejects mismatched placements.
        */
        eval-workload-role-placement =
          let
            result = import ../../../tests/eval/workload-role-placement.nix {
              inherit lib;
            };
          in
          pkgs.runCommandLocal "eval-workload-role-placement" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Ordered manifest selectors resolve to explicit realizations.
          Invalid, ambiguous, cardinality, and role combinations fail.
        */
        eval-placement-resolution =
          let
            result = import ../../../tests/eval/placement-resolution.nix { inherit lib; };
          in
          pkgs.runCommandLocal "eval-placement-resolution" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Adelie's post-admission source keeps application authority narrow,
          portable disks absent, and stateful backups remote to workstation.
        */
        eval-three-host-migration =
          let
            result = import ../../../tests/eval/three-host-migration.nix { inherit inputs lib; };
          in
          pkgs.runCommandLocal "eval-three-host-migration" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        eval-topology-conformance =
          let
            result = import ../../../tests/eval/topology-conformance.nix { inherit inputs lib; };
          in
          pkgs.runCommandLocal "eval-topology-conformance" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Canonical datasets project into producer and consumer runtime
          paths without duplicating their logical storage contract.
        */
        eval-datasets =
          let
            result = import ../../../tests/eval/datasets.nix {
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
            result = import ../../../tests/eval/product-artifacts.nix {
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
            result = import ../../../tests/eval/deployment.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-deployment" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          System adapters must be selected only by explicit profiles.
        */
        eval-system-profile-adapters =
          let
            result = import ../../../tests/eval/system-profile-adapters.nix {
              inherit pkgs lib inputs;
            };
          in
          pkgs.runCommandLocal "eval-system-profile-adapters" { } ''
            echo ${lib.escapeShellArg result} > $out
          '';

        /**
          Desktop setting contracts and the Waybar realization must derive
          from the same profile option.
        */
        desktop-settings-contract =
          let
            evaluated = inputs.self.nixosConfigurations.workstation.extendModules {
              modules = [
                {
                  home-manager.users.nori.nori.desktop.profile.components."desktop.waybar".position = "bottom";
                }
              ];
            };
            component = settings: {
              id = "test.component";
              title = "Test component";
              description = "Evaluation fixture.";
              inherit settings;
              readOnlyFields = { };
            };
            setting =
              overrides:
              {
                id = "test.setting";
                title = "Test setting";
                description = "Evaluation fixture.";
                group = "Test";
                control = "enum";
                scope = "user";
                applyClass = "generation";
                ownership = "user";
                runtimeAdapter = null;
                action = null;
              }
              // overrides;
            componentsEvaluate =
              contributions:
              (builtins.tryEval (
                builtins.deepSeq
                  (inputs.self.nixosConfigurations.workstation.extendModules {
                    modules = [
                      {
                        home-manager.users.nori.nori.desktop.componentContributions = lib.mkForce contributions;
                      }
                    ];
                  }).config.home-manager.users.nori.nori.desktop.components
                  true
              )).success;
            duplicateComponentFails =
              !componentsEvaluate [
                (component [ ])
                (component [ ])
              ];
            duplicateSettingFails =
              !componentsEvaluate [
                (component [
                  (setting { })
                  (setting { })
                ])
              ];
            unsupportedPresentationControlFails =
              !componentsEvaluate [
                (component [
                  (setting { control = "unsupported"; })
                ])
              ];
            home = evaluated.config.home-manager.users.nori;
            generated = home.nori.desktop.generated;
            polkitPolicy =
              evaluated.config.environment.etc."polkit-1/actions/org.nori.desktop-settings.policy".source;
            polkitRule = evaluated.config.security.polkit.extraConfig;
            hasActiveNoriRule =
              lib.hasInfix "action.id == \"org.nori.desktop-settings.activate\"" polkitRule
              && lib.hasInfix "subject.user == \"nori\"" polkitRule
              && lib.hasInfix "subject.active" polkitRule
              && lib.hasInfix "polkit.Result.AUTH_ADMIN" polkitRule;
            hasIngressRestartCoupling =
              evaluated.config.systemd.services.nori-desktop-config-ingress.partOf
              == [ "nori-desktop-config.service" ];
            settingsService = evaluated.config.systemd.services.nori-desktop-config;
            tmpfilesRules = evaluated.config.systemd.tmpfiles.rules;
            hasSafeRuntimeDirectory =
              settingsService.serviceConfig.RuntimeDirectory == "nori-desktop-settings"
              && settingsService.serviceConfig.RuntimeDirectoryMode == "0711"
              && !lib.elem "nori-desktop-settings" evaluated.config.users.users.nori.extraGroups;
            hasPrivateAuthorityLock =
              lib.elem "f /run/lock/nori-desktop-settings-activation.lock 0640 root nori-desktop-settings-authority -" tmpfilesRules
              && lib.elem "nori-desktop-settings-authority" evaluated.config.users.users.nori-desktop-settings.extraGroups
              && !lib.elem "nori-desktop-settings-authority" evaluated.config.users.users.nori.extraGroups;
            hasExactSocketPaths =
              lib.elem "NORI_DESKTOP_SETTINGS_SOCKET=/run/nori-desktop-settings/backend.sock" settingsService.serviceConfig.Environment
              && lib.hasInfix "/run/nori-desktop-settings/public.sock /run/nori-desktop-settings/backend.sock" evaluated.config.systemd.services.nori-desktop-config-ingress.serviceConfig.ExecStart;
            settingsPackage = home.nori.desktop.settingsService.package;
            inherit (generated) inputSchema;
            inherit (generated) outputSchema;
            inherit (generated) presentation;
            inherit (generated) resolvedSettings;
          in
          assert lib.assertMsg duplicateComponentFails "duplicate desktop component IDs must fail evaluation";
          assert lib.assertMsg duplicateSettingFails "duplicate desktop setting IDs must fail evaluation";
          assert lib.assertMsg unsupportedPresentationControlFails
            "unsupported presentation controls must fail evaluation";
          assert lib.assertMsg (
            home.programs.waybar.settings.mainBar.position == "bottom"
          ) "Waybar must consume the generated desktop profile option";
          assert lib.assertMsg hasActiveNoriRule
            "desktop settings polkit rule must authorize only active nori sessions";
          assert lib.assertMsg hasIngressRestartCoupling
            "desktop settings ingress must restart with its authority";
          assert lib.assertMsg hasSafeRuntimeDirectory
            "desktop settings runtime directory must be authority-owned, client-traversable, and not client-writable";
          assert lib.assertMsg hasPrivateAuthorityLock
            "desktop settings authority lock must exclude the desktop user";
          assert lib.assertMsg hasExactSocketPaths
            "desktop settings authority must use the fixed public and backend socket paths";
          pkgs.runCommandLocal "desktop-settings-contract"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.jq
              ];
            }
            ''
              jq -e '
                . as $schema
                | [."$defs"[] | select(.properties? and (.properties | has("desktop.waybar")))] as $roots
                | ($roots | length) == 1
                | $roots[0].properties["desktop.waybar"]["$ref"] as $componentRef
                | ($componentRef | ltrimstr("#/$defs/")) as $componentName
                | $schema["$defs"][$componentName] as $component
                | ($component.properties.position["$ref"] | ltrimstr("#/$defs/")) as $positionName
                | $schema["$defs"][$positionName].enum == ["top", "bottom"]
                | ($component.properties | keys == ["position"])
              ' ${generated.inputSchema} >/dev/null
              jq -e '
                . as $schema
                | [."$defs"[] | select(.properties? and (.properties | has("desktop.waybar")))] as $roots
                | ($roots | length) == 1
                | $roots[0].properties["desktop.waybar"]["$ref"] as $componentRef
                | ($componentRef | ltrimstr("#/$defs/")) as $componentName
                | $schema["$defs"][$componentName].properties
                | to_entries
                | length > 1 and all(.value.readOnly == true)
              ' ${generated.outputSchema} >/dev/null
              jq -e '
                ."desktop.waybar".settings.position.action.title
                == "Settings: Bar Position"
              ' ${generated.presentation} >/dev/null
              jq -e '
                ."desktop.waybar".position == "bottom"
              ' ${generated.resolvedSettings} >/dev/null
              test -e ${polkitPolicy}
              grep -Fx '  <action id="org.nori.desktop-settings.activate">' ${polkitPolicy} >/dev/null
              grep -Fx '      <allow_any>no</allow_any>' ${polkitPolicy} >/dev/null
              grep -Fx '      <allow_inactive>no</allow_inactive>' ${polkitPolicy} >/dev/null
              grep -Fx '      <allow_active>no</allow_active>' ${polkitPolicy} >/dev/null
              mkdir -p "$TMPDIR"/{config,state,data,home}
              chmod 700 "$TMPDIR"/{config,state,data,home}
              cp ${inputSchema} "$TMPDIR/data/settings-input.schema.json"
              cp ${outputSchema} "$TMPDIR/data/settings-output.schema.json"
              cp ${presentation} "$TMPDIR/data/components.json"
              cp ${resolvedSettings} "$TMPDIR/data/resolved-settings.json"
              printf '%s\n' '{"source":"/nix/store/approved-source","host":"workstation"}' \
                > "$TMPDIR/approved-source.json"
              : > "$TMPDIR/authority.lock"
              env -u XDG_RUNTIME_DIR \
                HOME="$TMPDIR/home" \
                NORI_DESKTOP_SETTINGS_CONFIG_HOME="$TMPDIR/config" \
                NORI_DESKTOP_SETTINGS_STATE_HOME="$TMPDIR/state" \
                NORI_DESKTOP_SETTINGS_DATA_DIR="$TMPDIR/data" \
                NORI_DESKTOP_SETTINGS_APPROVED_SOURCE="$TMPDIR/approved-source.json" \
                NORI_DESKTOP_SETTINGS_ACTIVE_METADATA="$TMPDIR/generation.json" \
                NORI_DESKTOP_SETTINGS_BUILDER=/does-not-run \
                NORI_DESKTOP_SETTINGS_EVALUATOR=/does-not-run \
                NORI_DESKTOP_SETTINGS_AUTHORITY_LOCK="$TMPDIR/authority.lock" \
                NORI_DESKTOP_SETTINGS_FLOCK=${pkgs.util-linux}/bin/flock \
                NORI_DESKTOP_SETTINGS_SOCKET="$TMPDIR/backend.sock" \
                ${settingsPackage}/bin/nori-desktop-settings-daemon \
                > "$TMPDIR/daemon.out" 2> "$TMPDIR/daemon.err" &
              daemon_pid=$!
              trap 'kill "$daemon_pid" 2>/dev/null || true; wait "$daemon_pid" 2>/dev/null || true' EXIT
              for _ in $(seq 1 100); do
                if test -S "$TMPDIR/backend.sock"; then
                  touch "$out"
                  exit 0
                fi
                sleep 0.05
              done
              cat "$TMPDIR/daemon.err" >&2
              exit 1
            '';

        /**
          Product preflight must add canonical option context when Clan rejects
          an unsupported writable setting type; the fixture derives its names
          so this literal can only come from the component model.
        */
        desktop-settings-unsupported-writable-type-diagnostic =
          pkgs.runCommandLocal "desktop-settings-unsupported-writable-type-diagnostic"
            {
              nativeBuildInputs = [ pkgs.nix ];
            }
            ''
              stderr=$TMPDIR/stderr
              if NIX_STATE_DIR=$TMPDIR/nix-state NIX_DB_DIR=$TMPDIR/nix-db \
                nix-instantiate --eval --strict --show-trace \
                ${../../../tests/eval/desktop-settings-unsupported-writable-type.nix} \
                --argstr nixpkgs ${pkgs.path} \
                --argstr clanCore ${inputs.clan-core-src} \
                --arg componentModel ${../../../users/nori/programs/desktop/component-model.nix} \
                > /dev/null 2>"$stderr"; then
                echo "unsupported writable type unexpectedly evaluated" >&2
                exit 1
              fi
              grep -F 'nori.desktop.profile.components."test.unsupported".value' "$stderr" >/dev/null || {
                cat "$stderr" >&2
                exit 1
              }
              touch "$out"
            '';

        /**
          The desktop resource detector must measure cgroup working set rather
          than inactive file cache retained after a child process exits.
        */
        steady-state-resource-alert-working-set =
          let
            detectorScript = builtins.head inputs.self.nixosConfigurations.workstation.config.home-manager.users.nori.systemd.user.services.steady-state-resource-alert.Service.ExecStart;
          in
          import ../../../tests/eval/steady-state-resource-alert.nix {
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
              check "docs-routes" \
                ${../../../docs/generated/routes.md} \
                ${inputs.self.packages.${system}.docs-routes}
              check "docs-topology" \
                ${../../../docs/generated/topology.md} \
                ${inputs.self.packages.${system}.docs-topology}
              check "docs-capabilities" \
                ${../../../docs/generated/capabilities.md} \
                ${inputs.self.packages.${system}.docs-capabilities}
              check "docs-backups" \
                ${../../../docs/generated/backups.md} \
                ${inputs.self.packages.${system}.docs-backups}
              check "docs-recovery-evidence" \
                ${../../../docs/generated/recovery-evidence.md} \
                ${inputs.self.packages.${system}.docs-recovery-evidence}
              check "docs-fs" \
                ${../../../docs/generated/fs.md} \
                ${inputs.self.packages.${system}.docs-fs}

              if [ $fail -eq 0 ]; then
                touch $out
              else
                echo
                echo "Generated docs drifted. Regenerate + commit any failures:"
                for name in routes topology capabilities backups recovery-evidence fs; do
                  echo "  nix build .#docs-$name -o /tmp/r && cp /tmp/r docs/generated/$name.md && chmod +w docs/generated/$name.md"
                done
                exit 1
              fi
            '';
      };
    };
}
