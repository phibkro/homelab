{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nori.clawpatrol;
  inherit (lib)
    concatMapStringsSep
    filter
    listToAttrs
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    types
    ;

  package = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.clawpatrol;
  credentialType = types.submodule {
    options = {
      sopsKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Key in secrets/apps.yaml. Null keeps the hostname allowed but injects
          no credential. Secret bytes are read from the sops runtime file.
        '';
      };
      secretSlot = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Optional Claw Patrol plugin secret slot. For example, ssh_key reads
          key material from the private_key slot rather than its bare value.
        '';
      };
    };
  };
  credentials = filter (entry: entry.sopsKey != null) (
    mapAttrsToList (name: value: {
      inherit name;
      inherit (value) sopsKey secretSlot;
    }) cfg.credentials
  );
  secretName = name: "clawpatrol-${name}";
  credentialEnvName =
    entry:
    "CLAWPATROL_SECRET_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] entry.name)}"
    + lib.optionalString (entry.secretSlot != null) "_${lib.toUpper entry.secretSlot}";
  credentialRef =
    name: type:
    if cfg.credentials.${name}.sopsKey == null then "passthrough.${name}" else "${type}.${name}";
  credentialBlock =
    name: type: endpoint: extra:
    if cfg.credentials.${name}.sopsKey == null then
      ''
        credential "passthrough" "${name}" {
          endpoint = https.${endpoint}
        }
      ''
    else
      ''
        credential "${type}" "${name}" {
          endpoint = https.${endpoint}
          ${extra}
        }
      '';
  gatewayConfig = ''
    schema_version = 1

    gateway {
      dashboard_listen       = "0.0.0.0:${toString cfg.dashboardPort}"
      public_url             = "https://clawpatrol.${config.nori.domain}"
      state_dir              = "/var/lib/clawpatrol"
      dashboard_config_writes = false
      telemetry              = false

      wireguard {
        subnet_cidr      = "${cfg.wireguardSubnet}"
        listen_port       = ${toString cfg.wireguardPort}
        endpoint          = "${
          config.nori.hosts.${config.networking.hostName}.tailnetIp
        }:${toString cfg.wireguardPort}"
        host_loopback_port = ${toString cfg.loopbackPort}
      }
    }

    defaults {
      unknown_host  = "deny"
      llm_fail_mode = "closed"
    }

    endpoint "https" "github"     { hosts = ["github.com"] }
    endpoint "https" "cloudflare" { hosts = ["api.cloudflare.com"] }
    endpoint "https" "openai"     { hosts = ["api.openai.com"] }
    endpoint "https" "anthropic"  { hosts = ["api.anthropic.com"] }
    endpoint "https" "huggingface" { hosts = ["huggingface.co"] }
    endpoint "https" "ntnu"       { hosts = ["www.ntnu.no"] }
    endpoint "ssh" "github-ssh"    { hosts = ["github.com:22"] }

    ${credentialBlock "github" "github_oauth" "github" ""}
    ${credentialBlock "cloudflare" "bearer_token" "cloudflare" ""}
    ${credentialBlock "openai" "bearer_token" "openai" ""}
    ${credentialBlock "anthropic" "anthropic_manual_key" "anthropic" ""}
    ${credentialBlock "huggingface" "bearer_token" "huggingface" ""}
    credential "passthrough" "ntnu" { endpoint = https.ntnu }
    credential "ssh_key" "github-ssh" { endpoint = ssh.github-ssh }

    rule "fleet-allowlisted-hosts" {
      endpoints = [
        https.github,
        https.cloudflare,
        https.openai,
        https.anthropic,
        https.huggingface,
        https.ntnu,
      ]
      verdict = "allow"
      reason  = "Host is in the reviewed fleet egress allowlist"
    }

    profile "default" {
      credentials = [
        ${credentialRef "github" "github_oauth"},
        ${credentialRef "cloudflare" "bearer_token"},
        ${credentialRef "openai" "bearer_token"},
        ${credentialRef "anthropic" "anthropic_manual_key"},
        ${credentialRef "huggingface" "bearer_token"},
        ssh_key.github-ssh,
        passthrough.ntnu,
      ]
    }
  '';
  configFile = pkgs.writeText "clawpatrol-gateway.hcl" gatewayConfig;
in
{
  options.nori.clawpatrol = {
    enable = mkEnableOption "Claw Patrol agent egress gateway" // {
      default = true;
    };
    dashboardPort = mkOption {
      type = types.port;
      default = 8092;
      description = "Operator dashboard port exposed through the canonical route.";
    };
    wireguardPort = mkOption {
      type = types.port;
      default = 51820;
      description = "WireGuard enrollment and agent traffic port.";
    };
    wireguardSubnet = mkOption {
      type = types.str;
      default = "10.55.0.0/24";
      description = "Private subnet allocated to enrolled Claw Patrol clients.";
    };
    loopbackPort = mkOption {
      type = types.port;
      default = 8443;
      description = "Gateway loopback landing port for same-host clients.";
    };
    configFile = mkOption {
      type = types.path;
      readOnly = true;
      description = "Generated non-secret gateway HCL.";
    };
    generatedConfig = mkOption {
      type = types.lines;
      readOnly = true;
      description = "Generated non-secret gateway HCL, exposed for policy tests.";
    };
    credentials = mkOption {
      type = types.submodule {
        options = {
          github = mkOption {
            type = credentialType;
            default = { };
          };
          github-ssh = mkOption {
            type = credentialType;
            default = {
              sopsKey = "github_ssh_private_key";
              secretSlot = "private_key";
            };
          };
          cloudflare = mkOption {
            type = credentialType;
            default.sopsKey = "cloudflare_api_token";
          };
          openai = mkOption {
            type = credentialType;
            default = { };
          };
          anthropic = mkOption {
            type = credentialType;
            default = { };
          };
          huggingface = mkOption {
            type = credentialType;
            default = { };
          };
        };
      };
      default = { };
      description = "Credential pool injected only by the gateway on matching egress.";
    };
  };

  config = mkIf cfg.enable {
    nori.clawpatrol = {
      inherit configFile;
      generatedConfig = gatewayConfig;
    };

    assertions = [
      {
        assertion = cfg.dashboardPort == config.nori.lanRoutes.clawpatrol.port;
        message = "nori.clawpatrol.dashboardPort must match the clawpatrol inventory endpoint";
      }
    ];

    users.users.clawpatrol = {
      isSystemUser = true;
      group = "clawpatrol";
      home = "/var/lib/clawpatrol";
      description = "Claw Patrol egress gateway";
    };
    users.groups.clawpatrol = { };

    sops.secrets = listToAttrs (
      map (
        entry:
        nameValuePair (secretName entry.name) {
          sopsFile = inputs.self + "/secrets/apps.yaml";
          key = entry.sopsKey;
          owner = "clawpatrol";
          group = "clawpatrol";
          mode = "0400";
        }
      ) credentials
    );

    # This file contains only @/run/secrets/... references. Claw Patrol reads
    # the bytes after startup; plaintext never enters the store or unit text.
    sops.templates.clawpatrol-credentials = {
      owner = "clawpatrol";
      group = "clawpatrol";
      mode = "0400";
      content = concatMapStringsSep "\n" (entry: ''
        ${credentialEnvName entry}=@${config.sops.secrets.${secretName entry.name}.path}
      '') credentials;
    };

    systemd.services.clawpatrol = {
      description = "Claw Patrol agent egress gateway";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "clawpatrol";
        Group = "clawpatrol";
        StateDirectory = "clawpatrol";
        StateDirectoryMode = "0700";
        UMask = "0077";
        EnvironmentFile = config.sops.templates.clawpatrol-credentials.path;
        ExecStartPre = "${package}/bin/clawpatrol validate ${configFile}";
        ExecStart = "${package}/bin/clawpatrol gateway ${configFile}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    networking.firewall.interfaces.tailscale0.allowedUDPPorts = [ cfg.wireguardPort ];

    nori.harden.clawpatrol.binds = [ "/var/lib/clawpatrol" ];
    nori.backups.clawpatrol = {
      include = [ "/var/lib/clawpatrol" ];
      tier = "service";
    };
  };
}
