/**
  Multi-host e2e — pi + workstation cross-host wiring.

  Boots TWO NixOS VMs on a shared synthetic vlan + verifies the
  compositions that single-host pi-smoke can't:

   - cross-host DNS:   workstation queries pi:53 via lanIp, gets the
                        right answer for a `*.test.lan` route.
   - cross-host proxy: pi runs caddy, workstation runs the backend.
                        Curl from anywhere on the vlan hits caddy on
                        pi, caddy proxies through to workstation,
                        backend's response comes back.

  Why this is the most valuable Layer-2 expansion beyond pi-smoke:
  the homelab's actual production shape is pi-on-entry-plane +
  workstation-on-backend. Single-host tests can verify caddy's
  module evals + binds :443, but not that the upstream resolves
  cleanly across the tailnet. Two real nodes on a real network
  exercise that path.

  Per docs/reference/testing-methodology.md "Real values, not stubs":
  same homelab modules production uses, same sops decryption, same
  caddy/blocky configs. Only the IPs are synthetic (vlan-private)
  and the tailnet identity is replaced by the test vlan IPs in
  nori.hosts.{pi,workstation}.tailnetIp.

  Invoked via `nix build .#checks.<system>.e2e-multi-host`.
*/
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  /*
    nixosTest's default network puts each node at 192.168.1.<N> on a
    shared vlan, where N is the node's position in the nodes attrset
    (1-indexed). Encoding the IPs here so the nori.hosts registry
    can use them as the synthetic "tailnetIp" for each host.
  */
  piIp = "192.168.1.1";
  workstationIp = "192.168.1.2";

  # Shared homelab module bundle — same imports both nodes use,
  # extracted to keep node configs readable.
  homelabBundle = [
    inputs.sops-nix.nixosModules.sops
    ../modules/infra/hosts.nix
    ../modules/infra/placement.nix
    ../modules/infra/capabilities
    ../modules/infra/storage
    ../modules/infra/backup
    ../modules/infra/networking
  ];

  # Synthetic nori.hosts registry — used by both nodes. Tailnet IPs
  # point at the vlan IPs so caddy's cross-host proxy resolution
  # (`config.nori.hosts.${runsOn}.tailnetIp`) lands on a real
  # reachable address.
  noriHosts = {
    pi = {
      tailnetIp = piIp;
      lanIp = piIp;
      role = "appliance";
      roleOneLiner = "";
      codename = "test-pi";
      hardware = "test-qemu";
      primaryJob = "entry-plane";
    };
    workstation = {
      tailnetIp = workstationIp;
      lanIp = workstationIp;
      role = "workhorse";
      roleOneLiner = "test workhorse";
      codename = "test-station";
      hardware = "test-qemu";
      primaryJob = "backend";
    };
  };

  # Common boot scaffolding + the test-mode caddy + sops overrides
  # already proven in tests/e2e-pi-smoke.nix. Imported by both node
  # configs to keep the per-node bodies focused on host-specific
  # wiring.
  commonNodeModule =
    { lib, ... }:
    {
      environment.etc."sops-test-age.txt".source = ./keys/test-age.txt;

      sops.age.keyFile = "/etc/sops-test-age.txt";
      sops.age.sshKeyPaths = lib.mkForce [ ];
      sops.defaultSopsFile = ./secrets/test.yaml;

      nori.hosts = noriHosts;
      nori.domain = "test.lan";

      nori.backupTargets.test-stub = {
        repository = "sftp:stub@stub.test:/stub";
        description = "test stub; never dialed";
      };
      sops.secrets.restic-password = { };

      nixpkgs.config = lib.mkForce {
        allowAliases = true;
        allowBroken = false;
        allowUnfree = false;
      };
      documentation.enable = lib.mkForce false;
      environment.systemPackages = [
        pkgs.bind.dnsutils
        pkgs.curl
      ];
    };
in

pkgs.testers.runNixOSTest {
  name = "e2e-multi-host";

  node.specialArgs = { inherit inputs; };

  nodes.pi =
    { config, lib, ... }:
    {
      imports = homelabBundle ++ [ commonNodeModule ];

      networking.hostName = "pi";
      nori.lanIp = lib.mkForce piIp;

      nori.lanRoutes.crossapp = {
        port = 7777;
        runsOn = "workstation";
      };

      nori.services.blocky.enable = true;
      nori.services.caddy.enable = true;
      nori.blocky.role = "self-hosted";

      services.caddy.package = lib.mkForce pkgs.caddy;
      services.caddy.globalConfig = lib.mkForce ''
        local_certs
      '';

      sops.secrets.cloudflare-acme-token.sopsFile = lib.mkForce ./secrets/test.yaml;

      networking.firewall.allowedTCPPorts = [
        53
        443
      ];
      networking.firewall.allowedUDPPorts = [ 53 ];
    };

  nodes.workstation =
    { config, lib, ... }:
    {
      imports = homelabBundle ++ [ commonNodeModule ];

      networking.hostName = "workstation";
      nori.lanIp = lib.mkForce piIp;

      # workstation needs the SAME lanRoute declaration so its
      # registry matches pi's. Without this the cross-host topology
      # would be silently lopsided.
      nori.lanRoutes.crossapp = {
        port = 7777;
        runsOn = "workstation";
      };

      # The actual backend that caddy on pi proxies to. Tiny python
      # HTTP server bound to :7777; responds with a deterministic
      # marker so the testScript can assert end-to-end roundtrip.
      systemd.services.crossapp-backend = {
        description = "Test backend on workstation — proves cross-host caddy proxy works";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "backend.py" ''
            import http.server
            class H(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    self.send_response(200)
                    self.send_header("Content-Type", "text/plain")
                    self.end_headers()
                    self.wfile.write(b"crossapp-from-workstation\n")
                def log_message(self, *a, **k): pass
            http.server.HTTPServer(("0.0.0.0", 7777), H).serve_forever()
          ''}";
        };
      };

      networking.firewall.allowedTCPPorts = [ 7777 ];
    };

  testScript = ''
    start_all()
    pi.wait_for_unit("multi-user.target")
    workstation.wait_for_unit("multi-user.target")

    with subtest("cross-host DNS: workstation queries pi:53, gets right answer"):
        # blocky's customDNS mapping on pi must resolve
        # crossapp.test.lan to nori.lanIp (piIp). workstation reaches
        # pi:53 directly over the vlan.
        pi.wait_for_unit("blocky.service")
        pi.wait_for_open_port(53)
        answer = workstation.succeed(
            "dig +short +time=2 +tries=1 crossapp.test.lan @${piIp}"
        ).strip()
        assert answer == "${piIp}", (
            f"crossapp.test.lan: workstation got {answer!r}, "
            "expected ${piIp}"
        )

    with subtest("cross-host backend: crossapp-backend on workstation is reachable"):
        # Sanity baseline — pi can reach the backend directly. If THIS
        # fails, the vlan or firewall is wrong, not the caddy proxy.
        workstation.wait_for_unit("crossapp-backend.service")
        workstation.wait_for_open_port(7777)
        direct = pi.succeed(
            "curl -fsS http://${workstationIp}:7777/"
        ).strip()
        assert direct == "crossapp-from-workstation", (
            f"direct fetch from pi → workstation:7777 failed: {direct!r}"
        )

    with subtest("cross-host caddy proxy: curl on workstation → pi:443 → workstation:7777"):
        # The real cross-host composition under test:
        # workstation curls https://crossapp.test.lan with --resolve
        # forcing the connection to pi's vlan IP. Caddy on pi terminates
        # TLS (internal CA), looks up upstream by runsOn=workstation
        # → workstationIp, proxies to :7777, gets the response, returns
        # it. End-to-end this validates: pi's caddy auto-vhost, the
        # `routeHost` resolution function, vlan reachability both ways.
        pi.wait_for_unit("caddy.service")
        pi.wait_for_open_port(443)
        response = workstation.succeed(
            "curl -fsS -k --resolve crossapp.test.lan:443:${piIp} "
            "https://crossapp.test.lan/"
        ).strip()
        assert response == "crossapp-from-workstation", (
            f"proxied response wrong: {response!r}"
        )
  '';
}
