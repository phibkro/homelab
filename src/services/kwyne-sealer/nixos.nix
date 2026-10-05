{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  deployment = builtins.fromJSON (builtins.readFile ./deployment.json);
  user = "kwyne-sealer";
  state = "/var/lib/${user}";
  sourceState = "/var/lib/kwyne-sealer-source";
  source = "${sourceState}/${deployment.revision}/sealer.js";
  settings = pkgs.writeText "kwyne-sealer.json" (
    builtins.toJSON {
      inherit (deployment)
        controlPlane
        authority
        repos
        pollIntervalMs
        ntfy
        ;
      stateDirectory = state;
    }
  );
  keys = {
    access-client-id = "kwyne-sealer-access-client-id";
    access-client-secret = "kwyne-sealer-access-client-secret";
    authority-token = "gitlab-kwyne-sealer-token";
    ntfy-topic = "ntfy-agents-channel";
    ntfy-token = "ntfy-publisher-token";
  };
  credential = name: key: "${name}:${config.sops.secrets.${key}.path}";
  provision = pkgs.writeShellApplication {
    name = "kwyne-sealer-provision";
    runtimeInputs = [
      pkgs.git
      pkgs.bun
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ./implementation/provision.sh;
  };
  run = pkgs.writeShellApplication {
    name = "kwyne-sealer-run";
    runtimeInputs = [
      pkgs.git
      pkgs.bun
      pkgs.coreutils
    ];
    text = ''
      set +x
      CF_ACCESS_CLIENT_ID="$(cat "$CREDENTIALS_DIRECTORY/access-client-id")"
      CF_ACCESS_CLIENT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/access-client-secret")"
      KWYNE_AUTHORITY_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/authority-token")"
      KWYNE_NTFY_TOPIC="$(cat "$CREDENTIALS_DIRECTORY/ntfy-topic")"
      KWYNE_NTFY_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/ntfy-token")"
      export CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET KWYNE_AUTHORITY_TOKEN KWYNE_NTFY_TOPIC KWYNE_NTFY_TOKEN
      exec bun ${source}
    '';
  };
  hardening = {
    UMask = "0077";
    ProtectSystem = "strict";
    PrivateDevices = true;
    ProtectControlGroups = true;
    ProtectKernelModules = true;
    CapabilityBoundingSet = "";
    LimitCORE = 0;
  };
in
{
  assertions = [
    {
      assertion = builtins.match "[0-9a-f]{40}" deployment.revision != null;
      message = "Kwyne sealer must pin a full sealed authority commit.";
    }
  ];
  users.groups.${user} = { };
  users.users.${user} = {
    isSystemUser = true;
    group = user;
    home = state;
  };
  nori.harden.${user} = { };
  nori.harden.kwyne-sealer-source = { };
  nori.backups.kwyne-sealer.skip = "Authority refs and receipts reconstruct the Git cache; notification cursors may replay idempotent messages. Credentials remain in SOPS.";
  sops.secrets = lib.genAttrs (builtins.attrValues keys) (key: {
    sopsFile = inputs.self + "/secrets/workstation-runtime.yaml";
    mode = lib.mkDefault "0400";
    restartUnits = [
      "kwyne-sealer.service"
    ]
    ++ lib.optional (key == keys.authority-token) "kwyne-sealer-source.service";
  });
  systemd.services.kwyne-sealer-source = {
    description = "Provision Kwyne sealer from pinned authority main";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "sops-install-secrets.service"
      "gitlab.service"
    ];
    before = [ "kwyne-sealer.service" ];
    environment = {
      KWYNE_SOURCE_REVISION = deployment.revision;
      KWYNE_SOURCE_REMOTE = deployment.repos.kwyne.remote;
      KWYNE_SOURCE_USERNAME = deployment.authority.username;
      KWYNE_SOURCE_DIRECTORY = sourceState;
      HOME = sourceState;
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
    serviceConfig = hardening // {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "kwyne-sealer-source";
      StateDirectoryMode = "0755";
      LoadCredential = [ (credential "authority-token" keys.authority-token) ];
      ExecStart = "${provision}/bin/kwyne-sealer-provision";
      TimeoutStartSec = "10min";
    };
  };
  systemd.services.${user} = {
    description = "Kwyne authority sealer and ntfy delivery";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    requires = [ "kwyne-sealer-source.service" ];
    after = [
      "network-online.target"
      "sops-install-secrets.service"
      "kwyne-sealer-source.service"
    ];
    environment = {
      HOME = state;
      KWYNE_SEALER_CONFIG = toString settings;
    };
    restartTriggers = [
      settings
      deployment.revision
    ];
    serviceConfig = hardening // {
      User = user;
      Group = user;
      StateDirectory = user;
      StateDirectoryMode = "0700";
      WorkingDirectory = state;
      LoadCredential = lib.mapAttrsToList credential keys;
      ExecStart = "${run}/bin/kwyne-sealer-run";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
