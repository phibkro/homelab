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
      checks =
        let
          sourceRoot = toString ../../..;
          workloadCatalog = import ../../../inventory/workloads.nix { inherit lib; };
          serviceRootFor =
            workload:
            let
              manifestPath = lib.removePrefix "${sourceRoot}/" (toString workload._manifestPath);
              manifestDirectory = builtins.dirOf manifestPath;
            in
            if builtins.baseNameOf manifestDirectory == "manifests" then
              builtins.dirOf manifestDirectory
            else
              manifestDirectory;
          catalogServiceRoots = lib.unique (
            map serviceRootFor (
              lib.attrValues (lib.filterAttrs (_: workload: workload ? runtimeModule) workloadCatalog)
            )
          );
          hardeningExceptionRoots = lib.unique (
            map serviceRootFor (
              lib.attrValues (lib.filterAttrs (_: workload: workload ? _hardeningException) workloadCatalog)
            )
          );
          mkCasePattern = patterns: lib.concatStringsSep "|" patterns;

          workstationHome = inputs.self.nixosConfigurations.workstation.config.home-manager.users.nori.home;
          homePackageNamed =
            name:
            builtins.head (builtins.filter (package: lib.getName package == name) workstationHome.packages);
          agentNotifyPackage = homePackageNamed "agent-notify";
          riceCommandPackage = homePackageNamed "rice-command";
        in
        {
          foundry-conventions =
            pkgs.runCommandLocal "foundry-conventions"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.findutils
                  pkgs.gnugrep
                  pkgs.gnused
                ];
              }
              ''
                bash ${../../../tests/conventions-check_test.sh} \
                  ${../../../foundry}/bin/conventions-check
                touch $out
              '';

          music-ingest-runtime =
            pkgs.runCommandLocal "music-ingest-runtime"
              {
                nativeBuildInputs = [
                  pkgs.b3sum
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.findutils
                  pkgs.util-linux
                ];
              }
              ''
                bash ${../../../services/music-ingest}/tests/runtime.sh
                touch $out
              '';

          # cd into the source so statix picks up `statix.toml` (looked up
          # from the working directory, not the path argument).
          statix = pkgs.runCommandLocal "statix" { } ''
            cd ${../../..}
            ${pkgs.statix}/bin/statix check . > $out
          '';

          /*
            --no-lambda-pattern-names: NixOS module convention is to
            declare `{ config, lib, pkgs, ... }:` even when not all are
            used; tolerate that. Still flags genuine unused
            let-bindings and other dead code.
          */
          deadnix = pkgs.runCommandLocal "deadnix" { } ''
            ${pkgs.deadnix}/bin/deadnix --fail --no-lambda-pattern-names ${../../..}
            touch $out
          '';

          agent-notify = pkgs.runCommandLocal "agent-notify-test" { } ''
            mkdir fake-bin
            cat > fake-bin/nori-alert <<'EOF'
            #!${pkgs.runtimeShell}
            touch "$AGENT_NOTIFY_CALLED"
            EOF
            chmod +x fake-bin/nori-alert

            called="$PWD/called"
            HERDR_ENV=1 AGENT_NOTIFY_CALLED="$called" PATH="$PWD/fake-bin:$PATH" \
              ${agentNotifyPackage}/bin/agent-notify claude stop </dev/null
            test -e "$called"

            rm "$called"
            HERDR_ENV=1 AGENT_NOTIFY_CALLED="$called" PATH="$PWD/fake-bin:$PATH" \
              ${agentNotifyPackage}/bin/agent-notify claude permission </dev/null
            test -e "$called"

            AGENT_NOTIFY_CALLED="$called" PATH="$PWD/fake-bin:$PATH" \
              ${agentNotifyPackage}/bin/agent-notify claude stop </dev/null
            test -e "$called"
            touch $out
          '';

          agent-post-edit =
            pkgs.runCommandLocal "agent-post-edit-test"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.git
                  pkgs.perl
                ];
              }
              ''
                bash ${../../../tests/hooks/post-edit-nix_test.sh} \
                  ${../../../tools/hooks/post-edit-nix.sh}
                touch $out
              '';

          pre-commit-hook =
            pkgs.runCommandLocal "pre-commit-hook-test"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.git
                  pkgs.jq
                  pkgs.gnugrep
                  pkgs.shellcheck
                ];
              }
              ''
                shellcheck ${../../../.githooks/pre-commit} ${../../../scripts/check-nix.sh} ${../../../tests/hooks/pre-commit_test.sh} ${../../../tests/hooks/check-nix_test.sh}
                bash ${../../../tests/hooks/pre-commit_test.sh} ${../../../.githooks/pre-commit}
                bash ${../../../tests/hooks/check-nix_test.sh} ${../../../scripts/check-nix.sh}
                touch $out
              '';

          format = pkgs.runCommandLocal "format" { } ''
            cp -R --no-preserve=mode ${../../..} source
            chmod -R u+w source
            ${pkgs.nixfmt-tree}/bin/treefmt --ci --tree-root "$PWD/source"
            touch $out
          '';

          hypr-rice-layout =
            pkgs.runCommandLocal "hypr-rice-layout"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gawk
                  pkgs.jq
                  pkgs.lua
                ];
              }
              ''
                lua ${../../../users/nori/programs/desktop/hypr-rice/layout_test.lua} \
                  ${../../../users/nori/programs/desktop/hypr-rice/layout.lua}
                lua ${../../../users/nori/programs/desktop/hypr-rice/rice_test.lua} \
                  ${../../../users/nori/programs/desktop/hypr-rice/layout.lua} \
                  ${../../../users/nori/programs/desktop/hypr-rice/rice.lua}
                bash ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout_test.sh} \
                  ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout.sh}
                bash ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout-menu_test.sh} \
                  ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout-menu.sh}
                bash ${../../../users/nori/programs/desktop/hypr-rice/tile-ratio_test.sh} \
                  ${../../../users/nori/programs/desktop/hypr-rice/tile-ratio.sh}
                luac -p ${../../../users/nori/programs/desktop/hypr-rice/layout.lua}
                luac -p ${../../../users/nori/programs/desktop/hypr-rice/rice.lua}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout_test.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout-menu.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout-menu_test.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/tile-ratio.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/tile-ratio_test.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout-live-test.sh}
                touch $out
              '';

          hypr-rice-launcher-projection =
            pkgs.runCommandLocal "hypr-rice-launcher-projection"
              {
                nativeBuildInputs = [
                  pkgs.findutils
                  pkgs.gnugrep
                  pkgs.jq
                ];
              }
              ''
                dispatcher=${riceCommandPackage}/bin/rice-command
                data_root=${workstationHome.activationPackage}/home-files/.local/share
                scripts="$data_root/vicinae/scripts/rice"
                manifest="$data_root/nori-desktop/actions.json"

                test -f "$manifest"
                test -d "$scripts"

                for script in "$scripts"/nori-rice-*; do
                  test -x "$script"
                  name=''${script##*/}
                  id=$(jq -r --arg script "rice/$name" \
                    'to_entries[] | select(.value.script == $script) | .key' "$manifest")
                  test -n "$id"
                  jq -e --arg id "$id" '.[$id].palette == true' "$manifest" >/dev/null
                  grep -Fxq '# @vicinae.schemaVersion 1' "$script"
                  grep -Fxq '# @vicinae.mode silent' "$script"
                  grep -Fxq "exec $dispatcher $id" "$script"
                done

                script_count=$(find "$scripts" -maxdepth 1 -name 'nori-rice-*' | wc -l)
                manifest_count=$(jq 'length' "$manifest")
                test "$script_count" -eq "$manifest_count"

                jq -e '
                  all(to_entries[];
                    (.key | test("^[a-z0-9]+([.-][a-z0-9]+)*$")) and
                    (.value.effect != "destructive" or .value.directBinding == null)
                  )
                ' "$manifest" >/dev/null

                generated_lua=${workstationHome.activationPackage}/home-files/.config/hypr/hyprland.lua
                jq -r 'to_entries[] | select(.value.directBinding != null) | .key' "$manifest" \
                  | while IFS= read -r id; do
                      grep -Fq "rice-command $id" "$generated_lua"
                    done

                if find ${workstationHome.activationPackage}/home-path/share/applications \
                  -maxdepth 1 -name 'nori-rice-*.desktop' -print -quit | grep -q ./.; then
                  echo 'private rice desktop entries leaked into the activated profile' >&2
                  exit 1
                fi

                set +e
                "$dispatcher" >/dev/null 2>&1
                test "$?" -eq 64
                "$dispatcher" unknown.command >/dev/null 2>&1
                test "$?" -eq 64
                set -e

                touch $out
              '';
          /*
            Migration path-coherence check
            were demoted to one-off scripts under lint/checks/ — invoked
            via `just check-migration` on demand. Their catch-rate at
            steady state is near-nil; the convention is set and new
            agents inherit it. The flake check overhead they imposed on
            every `nix flake check`/`nix develop`/CI run wasn't paying
            for itself. Re-promote if a future restructure phase pulls
            them back to non-zero catch rate.

            doc-coherence was deleted: it targeted the aurora-deferred-
            phase drift class (resolved 2026-06-16) and never generalized.
          */

          /**
            Routing table ↔ filesystem coherence. Body in
            lint/checks/routing-coherence.sh. Checks shared and scoped
            agent guides, the documentation map, and the onboarding query
            against the public inventory projection.
          */
          routing-coherence =
            pkgs.runCommandLocal "routing-coherence"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.jq
                  pkgs.gnugrep
                  pkgs.findutils
                  pkgs.coreutils
                ];
              }
              ''
                bash ${../../../lint/checks/routing-coherence.sh} ${../../..} \
                  ${pkgs.writeText "onboarding-inventory.json" (builtins.toJSON inputs.self.lib.noriInventory)}
                touch $out
              '';

          /**
            Every cataloged service root must own a backup intent: either
            `nori.backups.<name>.include` or an explicit
            `nori.backups.<name>.skip`. The workload catalog selects the roots,
            so helper and retired files outside active service ownership cannot
            create false positives.
          */
          every-service-has-backup-intent =
            pkgs.runCommandLocal "every-service-has-backup-intent"
              {
                nativeBuildInputs = [ pkgs.gnugrep ];
              }
              ''
                fail=0
                source_root=${../../..}
                for root in ${lib.escapeShellArgs catalogServiceRoots}; do
                  if ! grep -qRE --include='*.nix' 'nori\.backups\.' "$source_root/$root"; then
                    echo "✗ $root: no nori.backups.<name> declaration."
                    fail=1
                  fi
                done

                if [ "$fail" -eq 0 ]; then
                  touch "$out"
                else
                  echo
                  echo "Every cataloged service must declare a backup intent."
                  echo "See infra/common/nixos/backup.nix for the schema."
                  exit 1
                fi
              '';

          /**
            Every cataloged service root must own a filesystem-hardening intent
            through `nori.harden.<name>`. A workload can declare the private
            `_hardeningException` field only when the policy cannot apply. The
            inventory compiler validates and strips that field from public
            projections.
          */
          every-service-has-fs-hardening =
            pkgs.runCommandLocal "every-service-has-fs-hardening"
              {
                nativeBuildInputs = [ pkgs.gnugrep ];
              }
              ''
                fail=0
                source_root=${../../..}
                for root in ${lib.escapeShellArgs catalogServiceRoots}; do
                  case "$root" in
                    ${mkCasePattern hardeningExceptionRoots})
                      continue;;
                  esac
                  if ! grep -qRE --include='*.nix' 'nori\.harden\.' "$source_root/$root"; then
                    echo "✗ $root: no nori.harden.<name> declaration."
                    fail=1
                  fi
                done

                if [ "$fail" -eq 0 ]; then
                  touch "$out"
                else
                  echo
                  echo "Every cataloged service must declare a filesystem-hardening intent."
                  echo "See infra/common/nixos/service-hardening.nix for the schema."
                  exit 1
                fi
              '';

          /**
            Every shared infra module that declares `options.nori.*` is
            discovered recursively and must be explicitly accounted for.
            Runtime-observable effect schemas map to a `test-<X>` recipe.
            Hardware-bound and read-only projection schemas that were outside
            the original directory-default discovery are listed separately with
            their evaluation evidence. An unknown schema fails the check.

            This keeps the original runtime-test obligation for cross-cutting
            effects while closing the silent gap created when those schemas
            moved from concern directories into flat, purpose-named files.
          */
          infra-concerns-have-tests =
            let
              expectedRecipes = {
                "infra/common/nixos/alerts.nix" = "test-observability";
                "infra/common/nixos/backup.nix" = "test-backups";
                "infra/common/nixos/service-hardening.nix" = "test-harden";
                "infra/common/nixos/storage/default.nix" = "test-fs";
                "infra/common/nixos/storage/replication.nix" = "test-replicas";
              };
              evaluationOnlySchemas = {
                "infra/common/nixos/gpu.nix" =
                  "hardware-bound capability; host build and GPU service evaluation, outside the original */default.nix runtime-test scope";
                "infra/common/nixos/inventory.nix" =
                  "read-only projection; eval-inventory-public-safe and eval-deployment";
                "infra/common/nixos/wifi.nix" =
                  "hardware-bound network capability; Adelie system build and post-deployment network verification";
              };
              accountedSchemas = builtins.attrNames expectedRecipes ++ builtins.attrNames evaluationOnlySchemas;
            in
            pkgs.runCommandLocal "infra-concerns-have-tests"
              {
                nativeBuildInputs = [
                  pkgs.gnugrep
                  pkgs.findutils
                ];
              }
              ''
                cd ${../../..}
                fail=0

                # Walk the root Justfile + every co-located `*.just`
                # fragment (recipes are co-located with the concern they
                # operate on; see Justfile § "Co-location" for the map).
                # `find` traverses the tree so fragments at any depth
                # (tests/*.just, service-local fragments, …) get
                # scanned without an explicit allowlist.
                just_files="Justfile $(find . -name '*.just' -not -path './.git/*' -printf '%P\n' | sort | tr '\n' ' ')"

                # Discover every shared schema recursively. The explicit case
                # registry makes an unreviewed new options.nori.* file fail.
                check_discovered_schemas() {
                  local source_root="$1"
                  local discovered_fail=0
                  local path relative_path

                  while IFS= read -r path; do
                    if ! grep -qE 'options\.nori\.' "$path"; then
                      continue
                    fi

                    relative_path="''${path#"$source_root"/}"
                    case "$relative_path" in
                      ${lib.concatStringsSep "\n" (
                        map (path: ''
                          ${lib.escapeShellArg path}) ;;
                        '') accountedSchemas
                      )}
                      *)
                        echo "✗ $relative_path declares options.nori.* but is not accounted for"
                        echo "    Register its runtime recipe or its precise non-runtime evidence."
                        discovered_fail=1
                        ;;
                    esac
                  done < <(find "$source_root/infra/common/nixos" -type f -name '*.nix' | sort)

                  test "$discovered_fail" -eq 0
                }

                if ! check_discovered_schemas .; then
                  fail=1
                fi

                # Prove the discovery guard rejects a future unregistered
                # Reader-shaped schema rather than only accepting today's set.
                negative_root=$(mktemp -d)
                mkdir -p "$negative_root/infra/common/nixos"
                cat > "$negative_root/infra/common/nixos/unregistered.nix" <<'EOF' # path-coherence: skip — synthetic file is created during the check
                { lib, ... }:
                { options.nori.unregistered = lib.mkOption { type = lib.types.bool; }; }
                EOF
                negative_output="$negative_root/output"
                if check_discovered_schemas "$negative_root" >"$negative_output" 2>&1; then
                  echo "✗ schema discovery negative probe accepted an unregistered options.nori.* module"
                  fail=1
                elif ! grep -Fq 'infra/common/nixos/unregistered.nix declares options.nori.* but is not accounted for' "$negative_output"; then # path-coherence: skip — expected synthetic diagnostic
                  echo "✗ schema discovery negative probe failed without the expected diagnostic"
                  cat "$negative_output"
                  fail=1
                fi

                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (path: recipe: ''
                    if ! test -f ${lib.escapeShellArg path}; then
                      echo "✗ registered infra concern is missing: ${path}"
                      fail=1
                    elif ! grep -qE 'options\.nori\.' ${lib.escapeShellArg path}; then
                      echo "✗ ${path} no longer declares a Reader-shaped options.nori.* schema"
                      fail=1
                    elif ! grep -qhE '^@?${recipe}:' $just_files; then
                      echo "✗ ${path} → expected '${recipe}' recipe (not in: $just_files)"
                      fail=1
                    fi
                  '') expectedRecipes
                )}

                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (path: evidence: ''
                    if ! test -f ${lib.escapeShellArg path}; then
                      echo "✗ registered infra schema is missing: ${path}"
                      fail=1
                    elif ! grep -qE 'options\.nori\.' ${lib.escapeShellArg path}; then
                      echo "✗ ${path} no longer declares options.nori.*"
                      fail=1
                    fi
                    # Non-runtime evidence: ${evidence}
                  '') evaluationOnlySchemas
                )}

                if [ $fail -eq 0 ]; then
                  touch $out
                else
                  echo
                  echo "Every shared options.nori.* schema must be explicitly accounted for."
                  echo "Runtime-observable effects need a runtime-introspection recipe."
                  echo "See docs/reference/runtime-tests.md § 'Four levers' for the framework."
                  echo "Promotion register: docs/invariants.md § infra-concerns-have-tests."
                  exit 1
                fi
              '';
        };
    };
}
