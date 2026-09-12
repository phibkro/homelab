{
  nixpkgs,
  clanCore,
  componentModel,
}:
let
  pkgs = import nixpkgs { };
  lib = pkgs.lib;
  componentId = builtins.concatStringsSep "." [
    "test"
    "unsupported"
  ];
  settingId = builtins.concatStringsSep "" [
    "va"
    "lue"
  ];
  evaluated = lib.evalModules {
    specialArgs = {
      inherit pkgs;
      inputs = {
        clan-core-src = clanCore;
      };
    };
    modules = [
      {
        options = {
          assertions = lib.mkOption {
            type = lib.types.listOf lib.types.attrs;
            default = [ ];
          };
          nori.desktop.resolved.components = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
          xdg.dataFile = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
        };
      }
      componentModel
      {
        options.nori.desktop.profile.components.${componentId}.${settingId} = lib.mkOption {
          type = lib.types.functionTo lib.types.str;
        };
        config.nori.desktop.componentContributions = [
          {
            id = componentId;
            title = "Unsupported";
            description = "Unsupported writable type fixture.";
            settings = [
              {
                id = settingId;
                title = "Unsupported";
                description = "Unsupported writable type fixture.";
                group = "Test";
                control = "text";
                scope = "user";
                applyClass = "generation";
                ownership = "user";
                runtimeAdapter = null;
                action = null;
              }
            ];
          }
        ];
      }
    ];
  };
in
builtins.deepSeq evaluated.config.nori.desktop.generated.inputSchema true
