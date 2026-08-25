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
            Files under modules/services/ that aren't user-facing services —
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
            "modules/services/arr/runtime.nix"
            "modules/services/arr/shared.nix"
            "modules/services/lib.nix"
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
          # cd into the source so statix picks up `statix.toml` (looked up
          # from the working directory, not the path argument).
          statix = pkgs.runCommandLocal "statix" { } ''
            cd ${../../.}
            ${pkgs.statix}/bin/statix check . > $out
          '';

          /*
            --no-lambda-pattern-names: NixOS module convention is to
            declare `{ config, lib, pkgs, ... }:` even when not all are
            used; tolerate that. Still flags genuine unused
            let-bindings and other dead code.
          */
          deadnix = pkgs.runCommandLocal "deadnix" { } ''
            ${pkgs.deadnix}/bin/deadnix --fail --no-lambda-pattern-names ${../../.}
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
                bash ${../../tests/hooks/post-edit-nix_test.sh} \
                  ${../../tools/hooks/post-edit-nix.sh}
                touch $out
              '';

          format = pkgs.runCommandLocal "format" { } ''
            cp -R --no-preserve=mode ${../../.} source
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
                lua ${../../modules/home/desktop/hypr-rice/layout_test.lua} \
                  ${../../modules/home/desktop/hypr-rice/layout.lua}
                lua ${../../modules/home/desktop/hypr-rice/rice_test.lua} \
                  ${../../modules/home/desktop/hypr-rice/layout.lua} \
                  ${../../modules/home/desktop/hypr-rice/rice.lua}
                bash ${../../modules/home/desktop/hypr-rice/hypr-layout_test.sh} \
                  ${../../modules/home/desktop/hypr-rice/hypr-layout.sh}
                bash ${../../modules/home/desktop/hypr-rice/hypr-layout-menu_test.sh} \
                  ${../../modules/home/desktop/hypr-rice/hypr-layout-menu.sh}
                bash ${../../modules/home/desktop/hypr-rice/rice-launch_test.sh} \
                  ${../../modules/home/desktop/hypr-rice/rice-launch.sh}
                bash ${../../modules/home/desktop/hypr-rice/rice-palette_test.sh} \
                  ${../../modules/home/desktop/hypr-rice/rice-palette.sh}
                bash ${../../modules/home/desktop/hypr-rice/tile-ratio_test.sh} \
                  ${../../modules/home/desktop/hypr-rice/tile-ratio.sh}
                luac -p ${../../modules/home/desktop/hypr-rice/layout.lua}
                luac -p ${../../modules/home/desktop/hypr-rice/rice.lua}
                bash -n ${../../modules/home/desktop/hypr-rice/hypr-layout.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/hypr-layout_test.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/hypr-layout-menu.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/hypr-layout-menu_test.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/rice-launch.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/rice-launch_test.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/rice-palette.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/rice-palette_test.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/hypr-palette-live-test.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/tile-ratio.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/tile-ratio_test.sh}
                bash -n ${../../modules/home/desktop/hypr-rice/hypr-layout-live-test.sh}
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
                  -maxdepth 1 -name 'nori-rice-*.desktop' -print -quit | grep -q .; then
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
            Migration-era checks (path-coherence, multi-line-comments)
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
            lint/checks/routing-coherence.sh. Enforces that CLAUDE.md
            routes only to existing docs, every L2 doc is routed, and
            every L1 doc is both present + routed.
          */
          routing-coherence =
            pkgs.runCommandLocal "routing-coherence"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.gnugrep
                  pkgs.findutils
                  pkgs.coreutils
                ];
              }
              ''
                bash ${../../lint/checks/routing-coherence.sh} ${../../.}
                touch $out
              '';

          /**
            Every service module under modules/services/ must declare a
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
                cd ${../../.}
                fail=0

                # Excluded paths — see baseNonServicePatterns at the
                # top of `checks.${system}` for the shared list.
                for f in $(find modules/services -name '*.nix' | sort); do
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
                  echo "See modules/infra/backup/default.nix for the schema."
                  exit 1
                fi
              '';

          /**
            Every service module under modules/services/ must declare a
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
                cd ${../../.}
                fail=0

                # Shared exclusions in baseNonServicePatterns at the top  # multi-line: ok (bash heredoc)
                # of `checks.${system}`. Plus this check's specifics:
                #   * ntfy/notify.nix — template only, no service of its own
                #   * samba.nix       — legitimate /srv-full-access exception
                for f in $(find modules/services -name '*.nix' | sort); do
                  case "$f" in
                    ${
                      mkCasePattern (
                        baseNonServicePatterns
                        ++ [
                          "modules/infra/observability/ntfy/notify.nix"
                          "modules/services/samba/runtime.nix"
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
                  echo "See modules/infra/capabilities/default.nix for the schema."
                  exit 1
                fi
              '';

          /**
            Every `modules/infra/<X>/default.nix` that declares a
            Reader-shaped schema (options.nori.<name>) must ship a
            matching `test-<X>` runtime-introspection recipe in the
            Justfile. Codifies docs/reference/runtime-tests.md's
            "Four levers" framework: declaration at Reader level →
            generators at Writer level → runtime verification at
            test-* level. The convention prevents future infra
            additions from silently landing without their layer-3
            test (the failure mode that motivated audit findings
            #1 + #2 — silent harden/fs drift undetectable).

            Mapping registry. Each entry: directory name → expected
            Justfile recipe. Adding a new infra concern with Reader
            schema = adding one row OR the check fails.
          */
          infra-concerns-have-tests =
            let
              expectedRecipes = {
                backup = "test-backups";
                capabilities = "test-harden";
                networking = "test-routes";
                observability = "test-observability";
                storage = "test-fs";
                access = "test-authelia";
              };
            in
            pkgs.runCommandLocal "infra-concerns-have-tests"
              {
                nativeBuildInputs = [
                  pkgs.gnugrep
                  pkgs.findutils
                ];
              }
              ''
                cd ${../../.}
                fail=0

                # Find Reader-shaped infra concerns (directories with a
                # default.nix that declares options.nori.*).
                concerns=$(
                  for f in $(find modules/infra -maxdepth 2 -name 'default.nix' | sort); do
                    if grep -qE 'options\.nori\.' "$f"; then
                      basename "$(dirname "$f")"
                    fi
                  done
                )

                # Walk the root Justfile + every co-located `*.just`
                # fragment (recipes are co-located with the concern they
                # operate on; see Justfile § "Co-location" for the map).
                # `find` traverses the tree so fragments at any depth
                # (modules/infra/<X>/<X>.just, tests/tests.just, …) get
                # scanned without an explicit allowlist.
                just_files="Justfile $(find . -name '*.just' -not -path './.git/*' -printf '%P\n' | sort | tr '\n' ' ')"

                for concern in $concerns; do
                  case "$concern" in
                    ${lib.concatStringsSep "\n" (
                      lib.mapAttrsToList (dir: recipe: ''
                        ${dir})
                          if ! grep -qhE '^@?${recipe}:' $just_files; then
                            echo "✗ modules/infra/${dir}/ → expected '${recipe}' recipe (not in: $just_files)"
                            fail=1
                          fi
                          ;;
                      '') expectedRecipes
                    )}
                    *)
                      echo "✗ modules/infra/$concern/ declares options.nori.* but has no entry in expectedRecipes"
                      echo "    Add to flake.nix § checks.infra-concerns-have-tests with the recipe name"
                      echo "    that covers it, and ship the recipe in the Justfile or an imported *.just."
                      fail=1
                      ;;
                  esac
                done

                if [ $fail -eq 0 ]; then
                  touch $out
                else
                  echo
                  echo "Every Reader-shaped infra concern needs a runtime-introspection recipe."
                  echo "See docs/reference/runtime-tests.md § 'Four levers' for the framework."
                  echo "Promotion register: docs/invariants.md § infra-concerns-have-tests."
                  exit 1
                fi
              '';
        };
    };
}
