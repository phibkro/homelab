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
          /*
            Files under `services/` that aren't concrete service modules —
            folder aggregators, the *arr group's `media`-bootstrap helper,
            and the backup-cluster framework. Both `every-service-has-<X>`
            checks share this baseline; per-check additions (e.g. samba's
            /srv exception, notify@'s template-only file) are appended
            below at the call site.
          */
          baseNonServicePatterns = [
            "*/default.nix"
            "*/manifest.nix"
            "*/manifests/*.nix"
            "*/tests/*.nix"
            # Each path below moved from a legacy system concern and was never
            # in the service-catalog scanner's pre-migration input set.
            "services/agent-fix/nixos.nix" # failure-response mechanism
            "services/btrbk/nixos.nix" # snapshot/replication generator
            "services/greetd/nixos.nix" # graphical session mechanism
            "services/restic-backup/nixos.nix" # backup generator
            "services/restore-drill/nixos.nix" # backup verifier
            "services/sunshine/nixos.nix" # graphical session mechanism
            "services/tailscale/nixos.nix" # host networking mechanism
            "services/vector/nixos.nix" # host log-forwarding mechanism
          ];
          /**
            Generate a `case` glob from a list of patterns, joined with
            `|`. Used at the head of each scanner loop to skip framework
            / aggregator files.
          */
          mkCasePattern = ps: lib.concatStringsSep "|" ps;

          workstationHome = inputs.self.nixosConfigurations.workstation.config.home-manager.users.nori.home;
          homePackageNamed =
            name:
            builtins.head (builtins.filter (package: lib.getName package == name) workstationHome.packages);
          agentNotifyPackage = homePackageNamed "agent-notify";
          riceCommandPackage = homePackageNamed "rice-command";
          ricePalettePackage = homePackageNamed "rice-palette";
          confirmationNo = pkgs.writeShellScript "rice-confirm-no" ''
            printf '0'
          '';
          confirmationCancel = pkgs.writeShellScript "rice-confirm-cancel" ''
            exit 1
          '';
          confirmationInvalid = pkgs.writeShellScript "rice-confirm-invalid" ''
            printf '9'
          '';
        in
        {
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
                bash ${../../../users/nori/programs/desktop/hypr-rice/rice-launch_test.sh} \
                  ${../../../users/nori/programs/desktop/hypr-rice/rice-launch.sh}
                bash ${../../../users/nori/programs/desktop/hypr-rice/rice-palette_test.sh} \
                  ${../../../users/nori/programs/desktop/hypr-rice/rice-palette.sh}
                bash ${../../../users/nori/programs/desktop/hypr-rice/tile-ratio_test.sh} \
                  ${../../../users/nori/programs/desktop/hypr-rice/tile-ratio.sh}
                luac -p ${../../../users/nori/programs/desktop/hypr-rice/layout.lua}
                luac -p ${../../../users/nori/programs/desktop/hypr-rice/rice.lua}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout_test.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout-menu.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout-menu_test.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/rice-launch.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/rice-launch_test.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/rice-palette.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/rice-palette_test.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-palette-live-test.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/tile-ratio.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/tile-ratio_test.sh}
                bash -n ${../../../users/nori/programs/desktop/hypr-rice/hypr-layout-live-test.sh}
                touch $out
              '';

          hypr-rice-palette-projection =
            pkgs.runCommandLocal "hypr-rice-palette-projection"
              {
                nativeBuildInputs = [
                  pkgs.desktop-file-utils
                  pkgs.jq
                ];
              }
              ''
                palette_script=${ricePalettePackage}/bin/rice-palette
                dispatcher=${riceCommandPackage}/bin/rice-command
                private_data_root=$(grep -m1 '^export RICE_PRIVATE_DATA_DIR=' "$palette_script" | cut -d= -f2-)
                applications="$private_data_root/applications"
                manifest="$private_data_root/rice/commands.json"

                test -f "$manifest"
                test -d "$applications"

                for desktop in "$applications"/nori-rice-*.desktop; do
                  desktop-file-validate "$desktop"
                  id=''${desktop##*/nori-rice-}
                  id=''${id%.desktop}
                  grep -Fxq "Exec=$dispatcher $id" "$desktop"
                  jq -e --arg id "$id" '.[$id].palette == true' "$manifest" >/dev/null
                done

                desktop_count=$(find "$applications" -maxdepth 1 -name 'nori-rice-*.desktop' | wc -l)
                manifest_palette_count=$(jq '[to_entries[] | select(.value.palette)] | length' "$manifest")
                test "$desktop_count" -eq "$manifest_palette_count"

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
                FUZZEL_BIN=${confirmationNo} "$dispatcher" system.reboot
                test "$?" -eq 0
                FUZZEL_BIN=${confirmationCancel} "$dispatcher" system.poweroff
                test "$?" -eq 0
                FUZZEL_BIN=${confirmationInvalid} "$dispatcher" session.exit >/dev/null 2>&1
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
            Every service module under either service root must declare a
            backup intent — either `nori.backups.<name>.include = [...]`
            for what to back up, or `nori.backups.<name>.skip = "..."`
            for explicit opt-out. Forgetting to declare anything is the
            systemic cause of silent coverage gaps; this check turns
            forgetting into a build error.
          */
          every-service-has-backup-intent =
            pkgs.runCommandLocal "every-service-has-backup-intent"
              {
                nativeBuildInputs = [
                  pkgs.gnugrep
                  pkgs.findutils
                ];
              }
              ''
                cd ${../../..}
                fail=0

                # Excluded paths — see baseNonServicePatterns at the
                # top of `checks.${system}` for the shared list.
                test -d services
                for f in $(find services -name '*.nix' | sort); do
                  case "$f" in
                    ${mkCasePattern baseNonServicePatterns})
                      continue;;
                  esac
                  if ! grep -qE 'nori\.backups\.' "$f"; then
                    echo "✗ $f: no nori.backups.<name> declaration."
                    fail=1
                  fi
                done

                if [ $fail -eq 0 ]; then
                  touch $out
                else
                  echo
                  echo "Every service module must declare a backup intent."
                  echo "Either:"
                  echo "  nori.backups.<name>.include = [ \"/var/lib/<svc>\" ];"
                  echo "or:"
                  echo "  nori.backups.<name>.skip = \"<one-line reason>\";"
                  echo
                  echo "See infra/common/nixos/backup.nix for the schema."
                  exit 1
                fi
              '';

          /**
            Every service module under either service root must declare a
            filesystem-hardening intent via `nori.harden.<name>`. Same
            silent-coverage-gap rationale as `every-service-has-backup-
            intent`: forgetting to harden a new service means it inherits
            only upstream's defaults, which often leaves /mnt and /home
            visible. This check turns forgetting into a build error.
          */
          every-service-has-fs-hardening =
            pkgs.runCommandLocal "every-service-has-fs-hardening"
              {
                nativeBuildInputs = [
                  pkgs.gnugrep
                  pkgs.findutils
                ];
              }
              ''
                cd ${../../..}
                fail=0

                # Shared exclusions in baseNonServicePatterns at the top  # multi-line: ok (bash heredoc)
                # of `checks.${system}`. Plus this check's specifics:
                #   * ntfy/notify.nix — template only, no service of its own
                #   * samba.nix       — legitimate /srv-full-access exception
                test -d services
                for f in $(find services -name '*.nix' | sort); do
                  case "$f" in
                    ${
                      mkCasePattern (
                        baseNonServicePatterns
                        ++ [
                          "services/ntfy/nixos/notify.nix"
                          "services/samba/nixos.nix"
                        ]
                      )
                    })
                      continue;;
                  esac
                  if ! grep -qE 'nori\.harden\.' "$f"; then
                    echo "✗ $f: no nori.harden.<name> declaration."
                    fail=1
                  fi
                done

                if [ $fail -eq 0 ]; then
                  touch $out
                else
                  echo
                  echo "Every service module must declare a filesystem-hardening"
                  echo "intent via nori.harden.<service-name>. Default-deny baseline:"
                  echo "  ProtectHome=true, TemporaryFileSystem=[/mnt:ro,/srv:ro]"
                  echo "Set binds=[...] for writable paths, readOnlyBinds=[...] for"
                  echo "read-only, protectHome=null to leave upstream's value alone."
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
                "infra/common/nixos/gatus-probes.nix" = "test-observability";
                "infra/common/nixos/routes.nix" = "test-routes";
                "infra/common/nixos/service-hardening.nix" = "test-harden";
                "infra/common/nixos/storage/default.nix" = "test-fs";
                "infra/common/nixos/storage/replication.nix" = "test-replicas";
              };
              evaluationOnlySchemas = {
                "infra/common/nixos/gpu.nix" =
                  "hardware-bound capability; host build and GPU service evaluation, outside the original */default.nix runtime-test scope";
                "infra/common/nixos/hosts.nix" =
                  "injected topology; eval-deployment and eval-workload-role-placement";
                "infra/common/nixos/inventory.nix" =
                  "read-only projection; eval-inventory-public-safe and eval-deployment";
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
