/**
  disk-alert pipeline — threshold breach → ntfy POST.

  Same composition shape as Phase 7's notify@ pipeline (sops channel
  → curl → ntfy), but the trigger is different: disk-alert checks df
  on configured mountpoints and POSTs IF the usage crosses the
  critical threshold. The test sets the threshold artificially low so
  the check fires deterministically on the VM's own tmpfs root.

  What this catches:
   • disk-alert.service ExecStart drift (the script breaks silently
     and the alert never fires when a real workstation hits 95%)
   • mountpoint visibility under nori.harden (the readOnlyBinds
     plumbing — if it regresses, df fails inside the namespace and
     no alert posts)
   • sops decryption of ntfy-channel (the same path notify@ uses)

  Doesn't test the disk-alert.timer's schedule — that's nixpkgs +
  systemd's job and already exercised by Phase 3's heartbeat.timer.

  Invoked via `nix build .#checks.<system>.e2e-disk-alert`.
*/
{
  pkgs,
  lib,
  inputs,
  ...
}:

pkgs.testers.runNixOSTest {
  name = "e2e-disk-alert";

  node.specialArgs = { inherit inputs; };

  nodes.pi =
    { config, lib, ... }:
    {
      imports = [
        inputs.sops-nix.nixosModules.sops
        ../modules/infra/hosts.nix
        ../modules/infra/placement.nix
        ../modules/infra/capabilities
        ../modules/infra/storage
        ../modules/infra/backup
        ../modules/infra/networking
        ../modules/infra/observability/disk-alert.nix
        ../modules/infra/observability/ntfy/notify.nix
      ];

      environment.etc."sops-test-age.txt".source = ./keys/test-age.txt;
      sops.age.keyFile = "/etc/sops-test-age.txt";
      sops.age.sshKeyPaths = lib.mkForce [ ];
      sops.defaultSopsFile = ./secrets/test.yaml;
      sops.secrets.restic-password = { };

      networking.hostName = "pi";
      nori.domain = "test.lan";
      nori.lanIp = lib.mkForce "10.0.0.20";

      nori.hosts = {
        pi = {
          tailnetIp = "100.0.0.1";
          lanIp = "10.0.0.10";
          role = "appliance";
          roleOneLiner = "";
          codename = "test-pi";
          hardware = "test-qemu";
          primaryJob = "disk-alert";
        };
        workstation = {
          tailnetIp = "100.0.0.2";
          lanIp = "10.0.0.20";
          role = "workhorse";
          roleOneLiner = "test";
          codename = "test-station";
          hardware = "test-qemu";
          primaryJob = "—";
        };
      };

      nori.backupTargets.test-stub = {
        repository = "sftp:stub@stub.test:/stub";
        description = "test stub";
      };

      # Real disk-alert config, only with the knobs the test cares
      # about overridden: tmpfs root is ~100% used (always >0%), so
      # any threshold ≥1 fires. baseUrl → stub receiver.
      nori.services.disk-alert.enable = true;
      nori.observability.diskAlert = {
        mountpoints = [ "/" ];
        criticalThresholdPct = 1;
        baseUrl = "http://127.0.0.1:9999";
      };
      # ntfy-notify owns the sops.secrets.ntfy-channel declaration;
      # disk-alert just reads it. Production wires the same way
      # (every host that posts to ntfy imports notify.nix).
      nori.services.ntfy-notify.enable = true;

      # Phase 7's stub receiver pattern — captures POST bodies + headers
      # to a file so the testScript can assert on the alert shape.
      systemd.services.test-ntfy-receiver = {
        description = "Stub — captures ntfy POSTs from disk-alert";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          StateDirectory = "test-ntfy";
          ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "test-ntfy-receiver.py" ''
            import http.server
            class H(http.server.BaseHTTPRequestHandler):
                def do_POST(self):
                    n = int(self.headers.get("Content-Length", 0))
                    body = self.rfile.read(n).decode("utf-8", errors="replace")
                    with open("/var/lib/test-ntfy/messages", "a") as f:
                        f.write(f"PATH={self.path}\n")
                        for k, v in self.headers.items():
                            f.write(f"HDR {k}: {v}\n")
                        f.write(f"BODY={body}\n---\n")
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"ok")
                def log_message(self, *a, **k):
                    pass
            http.server.HTTPServer(("127.0.0.1", 9999), H).serve_forever()
          ''}";
        };
      };

      nixpkgs.config = lib.mkForce {
        allowAliases = true;
        allowBroken = false;
        allowUnfree = false;
      };
      documentation.enable = lib.mkForce false;
    };

  testScript = ''
    start_all()
    pi.wait_for_unit("multi-user.target")
    pi.wait_for_unit("test-ntfy-receiver.service")

    with subtest("disk-alert fires + POSTs through with the right shape"):
        # Sanity baseline — receiver hasn't captured anything yet.
        pi.succeed("test ! -s /var/lib/test-ntfy/messages || ! grep -q . /var/lib/test-ntfy/messages")

        # Trigger the watchdog directly (the timer fires it every 30min
        # in prod; we don't want to wait). The script is a oneshot so
        # this blocks until completion.
        pi.succeed("systemctl start disk-alert.service")

        # POST is synchronous within the script; the receiver should
        # have the message before systemctl returns.
        captured = pi.succeed("cat /var/lib/test-ntfy/messages")

        # URL path — channel from sops is "test-channel" (see
        # scripts/regen-test-secrets.sh). PATH=/<channel>.
        assert "PATH=/test-channel" in captured, (
            f"alert posted to wrong path: {captured!r}"
        )
        # Title header should carry "disk critical" + the mountpoint.
        assert "disk critical" in captured, (
            f"missing critical level in title: {captured!r}"
        )
        assert "(/ " in captured, (
            f"title missing the / mountpoint: {captured!r}"
        )
        # Urgency tier survived.
        assert "HDR Priority: urgent" in captured, (
            f"missing Priority: urgent: {captured!r}"
        )
        # Runbook link is in the body — operators clicking the
        # notification should reach the recovery procedure.
        assert "storage-full.md" in captured, (
            f"body missing runbook reference: {captured!r}"
        )
  '';
}
