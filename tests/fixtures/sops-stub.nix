{
  lib,
  config,
  ...
}:

/**
  Test fixture — stub sops-nix's option surface without real
  decryption.

  Why: nixosTest VMs don't have a sops decryption key that's a
  recipient for the real `secrets/secrets.yaml`. Real decryption at
  activation time would fail. The Phase-1 no-sops fixture force-
  emptied `sops.secrets`, which then broke any consumer that read
  `config.sops.secrets.<X>.path` (gatus, ntfy, caddy, authelia, …).

  This stub provides the SAME OPTION SURFACE as sops-nix's
  `nixosModules.sops`, but every secret's `.path` resolves to
  `/etc/test-secrets/<name>` instead of `/run/secrets/<name>`. A
  dummy file with `test-value-<name>` content is auto-planted at
  each path via `environment.etc`, so consumers reading the file
  at runtime get a valid (though dummy) file.

  Usage:
   - Do NOT also import `inputs.sops-nix.nixosModules.sops` — they
     would conflict on the same option declarations.
   - Do NOT import `modules/machines/base` (which pulls in
     sops-nix); compose only the infra concerns the test needs.
   - Service modules can declare `sops.secrets.X = {};` as usual
     and read `config.sops.secrets.X.path` — they'll get
     `/etc/test-secrets/X` with dummy content.

  Belongs under tests/fixtures/ per the e2e VM simulation spec
  (docs/specs/2026-06-17-e2e-vm-simulation.md § Q1).
*/

let
  inherit (lib) mkOption types;

  secretSubmodule =
    { name, ... }:
    {
      options = {
        path = mkOption {
          type = types.str;
          default = "/etc/test-secrets/${name}";
          description = "Resolved path of the (stubbed) secret.";
        };
        mode = mkOption {
          type = types.str;
          default = "0440";
        };
        owner = mkOption {
          type = types.str;
          default = "root";
        };
        group = mkOption {
          type = types.str;
          default = "root";
        };
        sopsFile = mkOption {
          type = types.either types.path types.str;
          default = "/dev/null";
        };
        format = mkOption {
          type = types.str;
          default = "yaml";
        };
        neededForUsers = mkOption {
          type = types.bool;
          default = false;
        };
        restartUnits = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        reloadUnits = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
      };
    };

  templateSubmodule =
    { name, ... }:
    {
      options = {
        path = mkOption {
          type = types.str;
          default = "/etc/test-secrets/${name}";
        };
        content = mkOption {
          type = types.str;
          default = "";
        };
        mode = mkOption {
          type = types.str;
          default = "0440";
        };
        owner = mkOption {
          type = types.str;
          default = "root";
        };
        group = mkOption {
          type = types.str;
          default = "root";
        };
        restartUnits = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
      };
    };
in

{
  options.sops = {
    defaultSopsFile = mkOption {
      type = types.either types.path types.str;
      default = "/dev/null";
    };
    validateSopsFiles = mkOption {
      type = types.bool;
      default = false;
    };

    age = {
      keyFile = mkOption {
        type = types.str;
        default = "/dev/null";
      };
      sshKeyPaths = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };

    gnupg = {
      home = mkOption {
        type = types.str;
        default = "/dev/null";
      };
      sshKeyPaths = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };

    secrets = mkOption {
      type = types.attrsOf (types.submodule secretSubmodule);
      default = { };
    };

    templates = mkOption {
      type = types.attrsOf (types.submodule templateSubmodule);
      default = { };
    };
  };

  config = {
    # Plant a dummy file at each declared secret's path. Services
    # reading config.sops.secrets.<X>.path get a real, readable
    # file at boot — dummy content, but valid for "does the unit
    # start" smoke tests.
    environment.etc = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "test-secrets/${name}" {
        text = "test-value-${name}";
        mode = "0440";
      }
    ) config.sops.secrets;
  };
}
