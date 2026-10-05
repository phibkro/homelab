# bundle is the output of implementation/provision.sh against the pinned authority.
# Kept explicit: the offline test never substitutes a fake sealer for the real program.
{
  pkgs,
  lib,
  inputs,
  bundle,
}:
let
  deployment = builtins.fromJSON (builtins.readFile ../deployment.json);
  inventory = inputs.self.lib.noriInventory;
  source = "/var/lib/kwyne-sealer-source/${deployment.revision}/sealer.js";
  settings = pkgs.writeText "sealer-offline.json" (
    builtins.toJSON {
      controlPlane = {
        url = "http://127.0.0.1:1";
        stage = "vm";
      };
      inherit (deployment) authority;
      repos.kwyne = {
        remote = "http://127.0.0.1:1/authority.git";
        branch = "main";
      };
      stateDirectory = "/var/lib/kwyne-sealer";
      pollIntervalMs = 500;
      ntfy.server = "http://127.0.0.1:1";
    }
  );
  names = [
    "access-client-id"
    "access-client-secret"
    "authority-token"
    "ntfy-topic"
    "ntfy-token"
  ];
in
pkgs.testers.runNixOSTest {
  name = "kwyne-sealer-offline";
  node.specialArgs = { inherit inputs; };
  nodes.sealer = { lib, ... }: {
    imports = [
      inputs.sops-nix.nixosModules.sops
      ../../../infra/common/nixos/inventory.nix
      ../../../infra/common/nixos/service-hardening.nix
      ../../../infra/common/nixos/backup.nix
      ../nixos.nix
    ];
    nori.inventory = inventory // {
      currentHost = "workstation";
      currentWorkloads = inventory.hosts.workstation.workloads;
    };
    sops.secrets = lib.mkForce { };
    documentation.enable = false;
    virtualisation.memorySize = 2048;
    environment.etc = lib.genAttrs (map (name: "sealer-test/${name}") names) (name: {
      text = "vm-sentinel-${lib.last (lib.splitString "/" name)}";
      mode = "0400";
    });
    systemd.services.kwyne-sealer-source = {
      environment = lib.mkForce { };
      preStart = ''
        ${pkgs.coreutils}/bin/install -D -m 0444 ${bundle} ${source}
      '';
      serviceConfig.LoadCredential = lib.mkForce [ ];
      serviceConfig.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
    };
    systemd.services.kwyne-sealer = {
      environment.KWYNE_SEALER_CONFIG = lib.mkForce (toString settings);
      serviceConfig.LoadCredential = lib.mkForce (map (name: "${name}:/etc/sealer-test/${name}") names);
    };
  };
  testScript = ''
    start_all()
    sealer.wait_for_unit("kwyne-sealer.service")
    sealer.wait_until_succeeds("journalctl -u kwyne-sealer --no-pager | grep -q 'Sealer started'")
    sealer.wait_until_succeeds("journalctl -u kwyne-sealer --no-pager | grep -q 'ControlPlaneUnavailable'")
    sealer.wait_until_succeeds("journalctl -u kwyne-sealer --no-pager | grep -q 'GitFailure'")
    pid = sealer.succeed("systemctl show -p MainPID --value kwyne-sealer").strip()
    environment = sealer.succeed(f"cat /proc/{pid}/environ").split("\x00")
    for name, value in {
        "CF_ACCESS_CLIENT_ID": "vm-sentinel-access-client-id",
        "CF_ACCESS_CLIENT_SECRET": "vm-sentinel-access-client-secret",
        "KWYNE_AUTHORITY_TOKEN": "vm-sentinel-authority-token",
        "KWYNE_NTFY_TOPIC": "vm-sentinel-ntfy-topic",
        "KWYNE_NTFY_TOKEN": "vm-sentinel-ntfy-token",
    }.items():
        assert f"{name}={value}" in environment
    logs = sealer.succeed("journalctl -u kwyne-sealer --no-pager")
    assert "vm-sentinel" not in logs
    sealer.succeed("test $(stat -c '%a:%U' /var/lib/kwyne-sealer) = '700:kwyne-sealer'")
    sealer.succeed("test $(stat -c '%a:%U' ${source}) = '444:root'")
    sealer.fail("sudo -u kwyne-sealer test -w ${source}")
    sealer.fail("sudo -u kwyne-sealer test -r /etc/sealer-test/authority-token")
    sealer.succeed("test -s /run/credentials/kwyne-sealer.service/authority-token")
    sealer.succeed("systemctl is-active kwyne-sealer")
  '';
}
