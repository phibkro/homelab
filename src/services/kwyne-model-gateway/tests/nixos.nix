{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  inventory = inputs.self.lib.noriInventory;
  hostName = lib.head inventory.workloads.kwyne-model-gateway.hosts;
  route = builtins.fromJSON (
    builtins.readFile ../../../infra/cloudflare/routes/kwyne-model-gateway.json
  );
in
pkgs.testers.runNixOSTest {
  name = "kwyne-model-gateway";
  node.specialArgs = { inherit inputs; };
  nodes.gateway = { lib, ... }: {
    imports = [
      inputs.sops-nix.nixosModules.sops
      ../../../infra/common/nixos/inventory.nix
      ../../../infra/common/nixos/service-hardening.nix
      ../../../infra/common/nixos/backup.nix
      ../nixos.nix
    ];
    nori.inventory = inventory // {
      currentHost = hostName;
      currentWorkloads = inventory.hosts.${hostName}.workloads;
    };
    documentation.enable = lib.mkForce false;
    virtualisation.memorySize = 2048;
    environment.systemPackages = [
      pkgs.curl
      pkgs.iproute2
    ];
    environment.etc."sops-test-age.txt".source = ../../../../tests/keys/test-age.txt;
    sops.age.keyFile = "/etc/sops-test-age.txt";
    sops.age.sshKeyPaths = lib.mkForce [ ];
    sops.defaultSopsFile = ../../../../tests/secrets/test.yaml;
    sops.secrets.kwyne-auth-broker-bearer.sopsFile = lib.mkForce ../../../../tests/secrets/test.yaml;
    sops.secrets.kwyne-model-gateway-bearer.sopsFile = lib.mkForce ../../../../tests/secrets/test.yaml;
    sops.secrets.restic-password = { };
  };
  testScript = ''
    start_all()
    gateway.wait_for_unit("kwyne-auth-broker.service")
    gateway.wait_for_unit("kwyne-auth-gateway.service")
    gateway.wait_until_succeeds("curl -fsS http://127.0.0.1:${toString route.brokerPort}/v1/healthz", timeout=120)
    gateway.wait_until_succeeds("curl -fsS http://127.0.0.1:${toString route.originPort}/healthz", timeout=120)
    listeners = gateway.succeed("ss -H -ltn")
    for port in (${toString route.brokerPort}, ${toString route.originPort}):
        addresses = [line.split()[3] for line in listeners.splitlines() if line.split()[3].endswith(f":{port}")]
        assert addresses == [f"127.0.0.1:{port}"], addresses
    url = "http://127.0.0.1:${toString route.originPort}/v1/models"
    status = gateway.succeed(f"curl -sS -o /dev/null -w '%{{http_code}}' {url}").strip()
    assert status == "401", status
    status = gateway.succeed(f"curl -sS -o /dev/null -w '%{{http_code}}' -H 'Authorization: Bearer vm-test-gateway-bearer-not-production' {url}").strip()
    assert status != "401", status
    print(f"Bearer-authenticated /v1/models with empty credential store: HTTP {status}")
    gateway.succeed("test $(stat -c '%a:%U' /var/lib/kwyne-auth-broker) = '700:kwyne-auth-broker'")
    gateway.succeed("test $(stat -c '%a:%U' /var/lib/kwyne-auth-gateway) = '700:kwyne-auth-gateway'")
    gateway.succeed("test $(stat -c '%a:%U' /var/lib/kwyne-auth-broker/auth-broker.token) = '600:kwyne-auth-broker'")
    gateway.succeed("test $(stat -c '%a:%U' /var/lib/kwyne-auth-gateway/auth-gateway.token) = '600:kwyne-auth-gateway'")
    gateway.fail("sudo -u kwyne-auth-gateway test -r /var/lib/kwyne-auth-broker/auth-broker.token")
    gateway.fail("kwyne-auth-broker-login unsupported-provider")
  '';
}
