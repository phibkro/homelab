{
  config,
  pkgs,
  lib,
  ...
}:
let
  cleanNodeSource =
    src:
    lib.cleanSourceWith {
      inherit src;
      filter =
        path: _type:
        let
          name = builtins.baseNameOf path;
        in
        name != "node_modules" && name != "dist";
    };
  settingsPackage = config.nori.desktop.settingsService.package;
  settingsCli = lib.getExe' settingsPackage "nori-desktop-settings";
  savedCommand = lib.getExe' settingsPackage "rice-saved-command";
  settingsFixtureImplementation = config.nori.desktop.settingsService.fixtureImplementation;
  settingsFixtureClient = "${settingsFixtureImplementation}/libexec/nori-desktop-settings";
  settingsFixtureSavedCommand = "${settingsFixtureImplementation}/libexec/rice-saved-command";
  savedCommandProjectionSync = pkgs.writeShellApplication {
    name = "nori-desktop-saved-command-projection-sync";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      for _ in {1..200}; do
        if ${settingsCli} state --json >/dev/null 2>&1; then
          exec ${savedCommand} sync
        fi
        sleep 0.05
      done
      printf '%s\n' 'nori-desktop-saved-command-projection-sync: settings service did not become ready' >&2
      exit 1
    '';
  };
  extensionStaticSource = cleanNodeSource ./extension;
  extensionSource =
    pkgs.runCommand "nori-desktop-vicinae-extension-source"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        mkdir -p "$out"
        cp -R ${extensionStaticSource}/. "$out"
        chmod -R u+w "$out"

        jq -n \
          --slurpfile components ${config.nori.desktop.generated.presentation} \
          --slurpfile inputSchema ${config.nori.desktop.generated.inputSchema} \
          '
            def deref($schema; $node):
              if ($node | type) != "object" then
                error("generated input schema contains a non-object reference")
              elif ($node["$ref"]? | type) == "string" then
                $node["$ref"] as $reference
                | if ($reference | startswith("#/$defs/")) then
                    $schema["$defs"][$reference | ltrimstr("#/$defs/")]
                    // error("generated input schema has an unresolved reference")
                  else
                    error("generated input schema has an unsupported reference")
                  end
              else
                $node
              end;

            def enumFor($componentId; $settingId):
              ($inputSchema[0]) as $schema
              | [
                  $schema["$defs"]
                  | to_entries[]
                  | select(.key | endswith("Input"))
                  | (deref($schema; .value)) as $root
                  | ($root.properties[$componentId] // empty) as $componentReference
                  | (deref($schema; $componentReference)) as $componentSchema
                  | ($componentSchema.properties[$settingId] // empty) as $settingReference
                  | deref($schema; $settingReference)
                  | select((.enum | type) == "array")
                ]
              | if length == 1 then
                  .[0].enum
                elif length == 0 then
                  error("generated input schema has no enum for \($componentId).\($settingId)")
                else
                  error("generated input schema has multiple enums for \($componentId).\($settingId)")
                end;

            def actionSettings:
              $components[0]
              | to_entries[]
              | .key as $componentId
              | .value.settings
              | to_entries[]
              | .key as $settingId
              | .value as $setting
              | select($setting.action != null and $setting.control == "enum")
              | {
                  componentId: $componentId,
                  settingId: $settingId,
                  values: enumFor($componentId; $settingId)
                };

            def unsupportedActionSettings:
              $components[0]
              | to_entries[]
              | .key as $componentId
              | .value.settings
              | to_entries[]
              | .key as $settingId
              | .value as $setting
              | select($setting.action != null and $setting.control != "enum")
              | "\($componentId).\($settingId)";

            [ actionSettings ] as $settings
            | [ unsupportedActionSettings ] as $unsupported
            | if ($unsupported | length) != 0 then
                error("generated setting actions require an enum control: \($unsupported | join(", "))")
              elif ($settings | length) == 0 then
                error("generated component catalog contains no setting actions")
              elif all($settings[]; (.values | length) != 0 and all(.values[]; type == "string")) then
                { settings: $settings }
              else
                error("generated setting enum contains a non-string or no values")
              end
          ' > "$out/settings-catalog.json"

        jq -n \
          --slurpfile manifest "$out/package.json" \
          --slurpfile components ${config.nori.desktop.generated.presentation} \
          --slurpfile catalog "$out/settings-catalog.json" \
          '
            def settingSlug($componentId; $settingId):
              ($componentId + "-" + $settingId)
              | ascii_downcase
              | gsub("[^a-z0-9]+"; "-")
              | sub("^-+"; "")
              | sub("-+$"; "");

            def commandName($componentId; $settingId):
              "settings-" + settingSlug($componentId; $settingId);

            ($manifest[0]) as $base
            | [
                $catalog[0].settings[]
                | . as $entry
                | $components[0][$entry.componentId].settings[$entry.settingId] as $setting
                | {
                    name: commandName($entry.componentId; $entry.settingId),
                    title: $setting.action.title,
                    subtitle: $setting.group,
                    description: $setting.action.description,
                    keywords: $setting.action.keywords,
                    mode: "view"
                  }
              ] as $commands
            | ($base | .commands + $commands) as $allCommands
            | if ($allCommands | map(.name) | unique | length) != ($allCommands | length) then
                error("duplicate Vicinae command name generated from desktop settings")
              else
                $base | .commands = $allCommands
              end
          ' > "$out/package.generated.json"

        while IFS=$'\t' read -r command componentId settingId values; do
          jq -n \
            --arg componentId "$componentId" \
            --arg settingId "$settingId" \
            --argjson values "$values" \
            '
              "import { SettingForm } from \"./settings-command\";\n\n"
              + "export default function GeneratedSettingAction() {\n"
              + "  return <SettingForm componentId=\($componentId | tojson) settingId=\($settingId | tojson) values={\($values | tojson)} />;\n"
              + "}\n"
            ' > "$out/src/$command.tsx"
        done < <(
          jq -r '
            def settingSlug($componentId; $settingId):
              ($componentId + "-" + $settingId)
              | ascii_downcase
              | gsub("[^a-z0-9]+"; "-")
              | sub("^-+"; "")
              | sub("-+$"; "");

            def commandName($componentId; $settingId):
              "settings-" + settingSlug($componentId; $settingId);

            .settings[]
            | [
                commandName(.componentId; .settingId),
                .componentId,
                .settingId,
                (.values | tojson)
              ]
            | @tsv
          ' "$out/settings-catalog.json"
        )

        mv "$out/package.generated.json" "$out/package.json"
        rm "$out/settings-catalog.json"
      '';
  noriDesktopExtension = config.lib.vicinae.mkExtension {
    name = "nori-desktop";
    src = extensionSource;
  };
  actions = lib.filterAttrs (_: action: action.palette) config.nori.desktop.actions;
  dispatcher = lib.getExe config.nori.desktop.actionDispatcher;
  singleLine =
    field: value:
    assert lib.assertMsg (
      builtins.match "[^\n\r]*" value != null
    ) "desktop action ${field} must fit on one line";
    value;
  scriptName = id: "nori-rice-${lib.replaceStrings [ "." ] [ "_" ] id}";
  actionScript =
    id: action:
    pkgs.writeShellScript (scriptName id) ''
      # @vicinae.schemaVersion 1
      # @vicinae.title ${singleLine "label" action.label}
      # @vicinae.mode silent
      # @vicinae.description ${singleLine "description" action.description}
      # @vicinae.keywords ${builtins.toJSON ([ action.category ] ++ action.keywords)}

      exec ${dispatcher} ${lib.escapeShellArg id}
    '';
  actionScripts = lib.mapAttrs actionScript actions;
  actionScriptFiles = lib.mapAttrs' (
    id: source:
    lib.nameValuePair "vicinae/scripts/rice/${scriptName id}" {
      inherit source;
    }
  ) actionScripts;
  actionScriptsPackage = pkgs.linkFarm "nori-desktop-vicinae-scripts" (
    lib.mapAttrsToList (id: path: {
      name = scriptName id;
      inherit path;
    }) actionScripts
  );
  actionCatalog = pkgs.writeText "nori-desktop-actions.json" (
    builtins.toJSON (
      lib.mapAttrs (id: action: {
        inherit (action)
          category
          description
          directBinding
          effect
          keywords
          label
          palette
          ;
        script = "rice/${scriptName id}";
      }) actions
    )
  );
  vicinaeLauncherLiveTest = pkgs.writeShellApplication {
    name = "vicinae-launcher-live-test";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.sway
      pkgs.util-linux
    ];
    text = ''
      export RICE_VICINAE_ACTION_SCRIPTS=${lib.escapeShellArg actionScriptsPackage}
      export RICE_VICINAE_EXTENSION=${lib.escapeShellArg noriDesktopExtension}
      export RICE_SAVED_COMMAND_BIN=${lib.escapeShellArg settingsFixtureSavedCommand}
      export RICE_NORI_DESKTOP_SETTINGS_BIN=${lib.escapeShellArg settingsFixtureClient}
      export RICE_DESKTOP_COMPONENTS=${lib.escapeShellArg config.nori.desktop.generated.presentation}
      export RICE_DESKTOP_INPUT_SCHEMA=${lib.escapeShellArg config.nori.desktop.generated.inputSchema}
      export RICE_DESKTOP_OUTPUT_SCHEMA=${lib.escapeShellArg config.nori.desktop.generated.outputSchema}
      export RICE_DESKTOP_RESOLVED_SETTINGS=${lib.escapeShellArg config.nori.desktop.generated.resolvedSettings}
      export RICE_VICINAE_BIN=${lib.escapeShellArg (lib.getExe pkgs.vicinae)}
      export RICE_VICINAE_TEST_SHELL=${lib.escapeShellArg (lib.getExe pkgs.bash)}
      ${builtins.readFile ./vicinae-launcher-live-test.sh}
    '';
  };
in
{
  programs.vicinae = {
    enable = true;
    enableFirefoxIntegration = false;
    systemd = {
      enable = true;
      target = config.wayland.systemd.target;
    };
    extensions = [ noriDesktopExtension ];
    settings.launcher_window.layer_shell.enabled = true;
  };

  home.packages = [ vicinaeLauncherLiveTest ];

  systemd.user.services = {
    vicinae = {
      Service = {
        ExecStartPre = lib.getExe savedCommandProjectionSync;
        Environment = [
          "RICE_NORI_DESKTOP_SETTINGS_BIN=${settingsCli}"
          "RICE_SAVED_COMMAND_BIN=${savedCommand}"
        ];
      };
    };
  };

  xdg.dataFile = actionScriptFiles // {
    "nori-desktop/actions.json".source = actionCatalog;
  };
}
