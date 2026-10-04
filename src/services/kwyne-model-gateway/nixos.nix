{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  omp = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
  route = builtins.fromJSON (
    builtins.readFile ../../infra/cloudflare/routes/kwyne-model-gateway.json
  );
  brokerUser = "kwyne-auth-broker";
  gatewayUser = "kwyne-auth-gateway";
  brokerState = "/var/lib/${brokerUser}";
  gatewayState = "/var/lib/${gatewayUser}";
  # The pinned OMP joins PI_CONFIG_DIR to HOME, even for an absolute value.
  # A relative dot keeps its canonical store exactly in the private state dir.
  configFolder = ".";
  brokerUrl = "http://${route.originHost}:${toString route.brokerPort}";
  login = pkgs.writeShellApplication {
    name = "kwyne-auth-broker-login";
    text = ''
      if [ "$#" -ne 1 ]; then
        echo 'Usage: kwyne-auth-broker-login anthropic|openai-codex' >&2
        exit 2
      fi
      case "$1" in anthropic|openai-codex) ;; *) echo 'Unsupported broker login provider' >&2; exit 2;; esac
      exec /run/wrappers/bin/sudo -u ${brokerUser} ${pkgs.coreutils}/bin/env -i \
        HOME=${brokerState} PI_CONFIG_DIR=${configFolder} TERM="''${TERM:-xterm}" \
        PATH=${
          lib.makeBinPath [
            omp
            pkgs.coreutils
            pkgs.openssh
          ]
        } \
        ${omp}/bin/omp auth-broker login "$1"
    '';
  };
  common = user: {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "sops-install-secrets.service"
    ];
    environment = {
      HOME = "/var/lib/${user}";
      PI_CONFIG_DIR = configFolder;
    };
    serviceConfig = {
      User = user;
      Group = user;
      StateDirectory = user;
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/${user}";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = "5s";
      ProtectSystem = "strict";
      PrivateDevices = true;
      ProtectControlGroups = true;
      ProtectKernelModules = true;
      CapabilityBoundingSet = "";
      LimitCORE = 0;
    };
  };
in
{
  assertions = [
    {
      assertion = route.originHost == "127.0.0.1";
      message = "The Kwyne broker and gateway must bind IPv4 loopback only.";
    }
  ];
  users.groups.${brokerUser} = { };
  users.groups.${gatewayUser} = { };
  users.users.${brokerUser} = {
    isSystemUser = true;
    group = brokerUser;
    home = brokerState;
  };
  users.users.${gatewayUser} = {
    isSystemUser = true;
    group = gatewayUser;
    home = gatewayState;
  };
  environment.systemPackages = [ login ];
  sops.secrets.kwyne-auth-broker-bearer = {
    sopsFile = inputs.self + "/secrets/workstation-runtime.yaml";
    mode = "0400";
    restartUnits = [
      "kwyne-auth-broker.service"
      "kwyne-auth-gateway.service"
    ];
  };
  sops.secrets.kwyne-model-gateway-bearer = {
    sopsFile = inputs.self + "/secrets/workstation-runtime.yaml";
    mode = "0400";
    restartUnits = [ "kwyne-auth-gateway.service" ];
  };
  nori.harden.${brokerUser} = { };
  nori.harden.${gatewayUser} = { };
  # OAuth is deliberately re-established by the operator after data loss.
  # No provider credential archive is projected to another host.
  nori.backups.kwyne-model-gateway.skip = "Provider OAuth credentials stay in the broker vault; the operator logs in again after loss. Bearers and Access credentials are in SOPS.";
  systemd.services.${brokerUser} = lib.recursiveUpdate (common brokerUser) {
    description = "Kwyne dedicated OMP credential broker";
    preStart = ''
      ${pkgs.coreutils}/bin/install -m 0600 "$CREDENTIALS_DIRECTORY/auth-broker.token" ${brokerState}/auth-broker.token
    '';
    serviceConfig = {
      LoadCredential = [ "auth-broker.token:${config.sops.secrets.kwyne-auth-broker-bearer.path}" ];
      ExecStart = "${omp}/bin/omp auth-broker serve --bind=${route.originHost}:${toString route.brokerPort}";
    };
  };
  systemd.services.${gatewayUser} = lib.recursiveUpdate (common gatewayUser) {
    description = "Kwyne broker-backed OMP model gateway";
    after = [
      "network-online.target"
      "sops-install-secrets.service"
      "kwyne-auth-broker.service"
    ];
    requires = [ "kwyne-auth-broker.service" ];
    environment.OMP_AUTH_BROKER_URL = brokerUrl;
    preStart = ''
      ${pkgs.coreutils}/bin/install -m 0600 "$CREDENTIALS_DIRECTORY/auth-broker.token" ${gatewayState}/auth-broker.token
      ${pkgs.coreutils}/bin/install -m 0600 "$CREDENTIALS_DIRECTORY/auth-gateway.token" ${gatewayState}/auth-gateway.token
    '';
    serviceConfig = {
      LoadCredential = [
        "auth-broker.token:${config.sops.secrets.kwyne-auth-broker-bearer.path}"
        "auth-gateway.token:${config.sops.secrets.kwyne-model-gateway-bearer.path}"
      ];
      ExecStart = "${omp}/bin/omp auth-gateway serve --bind=${route.originHost}:${toString route.originPort}";
    };
  };
}
