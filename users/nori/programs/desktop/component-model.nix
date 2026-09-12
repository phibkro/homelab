{
  config,
  inputs,
  lib,
  options,
  pkgs,
  ...
}:
let
  settingPresentationType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Stable setting identity within its component.";
      };
      title = lib.mkOption { type = lib.types.str; };
      description = lib.mkOption { type = lib.types.str; };
      group = lib.mkOption { type = lib.types.str; };
      control = lib.mkOption {
        type = lib.types.enum [
          "boolean"
          "enum"
          "text"
          "number"
          "list"
          "group"
        ];
      };
      scope = lib.mkOption {
        type = lib.types.enum [
          "user"
          "system"
        ];
      };
      applyClass = lib.mkOption {
        type = lib.types.enum [
          "live"
          "live-generation"
          "generation"
        ];
      };
      ownership = lib.mkOption {
        type = lib.types.enum [ "user" ];
        description = "The profile owner allowed to change this setting.";
      };
      runtimeAdapter = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Named runtime adapter reconciled after a matching activation.";
      };
      action = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              title = lib.mkOption { type = lib.types.str; };
              description = lib.mkOption { type = lib.types.str; };
              keywords = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            };
          }
        );
        default = null;
      };
    };
  };
  readOnlyPresentationType = lib.types.submodule {
    options = {
      title = lib.mkOption { type = lib.types.str; };
      description = lib.mkOption { type = lib.types.str; };
      reason = lib.mkOption { type = lib.types.str; };
    };
  };
  componentType = lib.types.submodule {
    options = {
      id = lib.mkOption { type = lib.types.str; };
      title = lib.mkOption { type = lib.types.str; };
      description = lib.mkOption { type = lib.types.str; };
      settings = lib.mkOption {
        type = lib.types.listOf settingPresentationType;
        default = [ ];
      };
      readOnlyFields = lib.mkOption {
        type = lib.types.attrsOf readOnlyPresentationType;
        default = { };
      };
    };
  };
  componentOutputType = lib.types.submodule {
    options = {
      id = lib.mkOption { type = lib.types.str; };
      title = lib.mkOption { type = lib.types.str; };
      description = lib.mkOption { type = lib.types.str; };
      settings = lib.mkOption {
        type = lib.types.attrsOf settingPresentationType;
        default = { };
      };
      readOnlyFields = lib.mkOption {
        type = lib.types.attrsOf readOnlyPresentationType;
        default = { };
      };
    };
  };
  contributions = config.nori.desktop.componentContributions;
  componentIds = map (component: component.id) contributions;
  duplicateComponentIds = lib.filter (id: lib.count (candidate: candidate == id) componentIds > 1) (
    lib.unique componentIds
  );
  duplicateSettingIds =
    component:
    let
      settingIds = map (setting: setting.id) component.settings;
    in
    lib.filter (id: lib.count (candidate: candidate == id) settingIds > 1) (lib.unique settingIds);
  duplicateSettingMessages = lib.concatMap (
    component:
    let
      duplicates = duplicateSettingIds component;
    in
    lib.optional (duplicates != [ ]) "${component.id}: ${lib.concatStringsSep ", " duplicates}"
  ) contributions;
  components = builtins.listToAttrs (
    map (
      component:
      lib.nameValuePair component.id (
        component
        // {
          settings = builtins.listToAttrs (
            map (setting: lib.nameValuePair setting.id setting) component.settings
          );
        }
      )
    ) contributions
  );
  clanLib = import "${inputs.clan-core-src}/lib/default.nix" { inherit lib; };
  inputSchema = clanLib.jsonschema.fromOptions {
    typePrefix = "NoriDesktopSettings";
    input = true;
    output = false;
    readOnly = {
      input = false;
      output = true;
    };
  } options.nori.desktop.profile.components;
  outputSchema = clanLib.jsonschema.fromOptions {
    typePrefix = "NoriDesktopSettings";
    input = false;
    output = true;
    readOnly = {
      input = false;
      output = true;
    };
  } options.nori.desktop.resolved.components;
  inputSchemaFile = pkgs.writeText "nori-desktop-settings-input.schema.json" (
    builtins.toJSON inputSchema
  );
  outputSchemaFile = pkgs.writeText "nori-desktop-settings-output.schema.json" (
    builtins.toJSON outputSchema
  );
  presentationFile = pkgs.writeText "nori-desktop-components.json" (builtins.toJSON components);
  resolvedFile = pkgs.writeText "nori-desktop-resolved-settings.json" (
    builtins.toJSON config.nori.desktop.resolved.components
  );
in
{
  options.nori.desktop = {
    componentContributions = lib.mkOption {
      type = lib.types.listOf componentType;
      default = [ ];
      internal = true;
      description = "Desktop component declarations before unique-ID composition.";
    };

    components = lib.mkOption {
      type = lib.types.attrsOf componentOutputType;
      readOnly = true;
      internal = true;
      description = "Uniquely composed desktop components.";
    };

    profile = {
      formatVersion = lib.mkOption {
        type = lib.types.literal 1;
        default = 1;
        internal = true;
      };
      revision = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 0;
        internal = true;
      };
    };

    generated = {
      inputSchema = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        internal = true;
      };
      outputSchema = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        internal = true;
      };
      presentation = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        internal = true;
      };
      resolvedSettings = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        internal = true;
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = duplicateComponentIds == [ ];
        message = "duplicate desktop component IDs: ${lib.concatStringsSep ", " duplicateComponentIds}";
      }
    ]
    ++ lib.concatMap (
      component:
      let
        duplicates = duplicateSettingIds component;
      in
      lib.optional (duplicates != [ ]) {
        assertion = false;
        message = "duplicate desktop setting IDs in ${component.id}: ${lib.concatStringsSep ", " duplicates}";
      }
    ) contributions;

    nori.desktop = {
      components =
        assert lib.assertMsg (
          duplicateComponentIds == [ ]
        ) "duplicate desktop component IDs: ${lib.concatStringsSep ", " duplicateComponentIds}";
        assert lib.assertMsg (
          duplicateSettingMessages == [ ]
        ) "duplicate desktop setting IDs: ${lib.concatStringsSep "; " duplicateSettingMessages}";
        components;
      generated = {
        inputSchema = inputSchemaFile;
        outputSchema = outputSchemaFile;
        presentation = presentationFile;
        resolvedSettings = resolvedFile;
      };
    };

    xdg.dataFile = {
      "nori-desktop/settings-input.schema.json".source = inputSchemaFile;
      "nori-desktop/settings-output.schema.json".source = outputSchemaFile;
      "nori-desktop/components.json".source = presentationFile;
      "nori-desktop/resolved-settings.json".source = resolvedFile;
    };
  };
}
