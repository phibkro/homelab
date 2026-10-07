/**
  disk-alert pipeline — allocation-pressure classification → ntfy POST.

  The alarm measures through the shared pressure construct
  (`nori.storagePressure.package`) and runs the shared alarm body
  (`src/infra/common/nixos/storage/pressure-alarm.bash`). This test exercises
  that composition against real filesystems: the VM's own (non-btrfs) root for
  the CLI contract and its error path, and a **real disposable btrfs volume**
  (blank disk → `mkfs.btrfs` → mount at /mnt/nori-pressure-test) for the
  alert. The ordinary threshold keeps its production default (95) while the
  metadata thresholds are test-local, so the alert about that volume can only
  come from metadata pressure with scarce expansion workspace — exactly the
  boundary the spec names, measured by the production raw-byte parser,
  observed through the read-only bind the unit runs under, and delivered by
  the real nori.alerts path.

  Uncertain classification boundaries (malformed/inconsistent/degraded
  measurements, the warning alert and its stamp lifecycle, the bounded
  maintenance argv, per-filesystem dedup) stay in
  `src/infra/common/nixos/storage/pressure.test.sh`, which drives the same CLI
  and the same alarm body against fixture bytes.

  What this catches:
   • the packaged CLI's measurement contract on real filesystems, including
     that an unmeasurable path is an error, never a healthy result
   • metadata-driven critical classification on a real btrfs volume, with the
     affected mountpoint and the raw allocation bytes in the alert body
   • disk-alert.service wiring drift (package path, unit environment, alert
     body, threshold carried from diskAlert.criticalThresholdPct)
   • critical alert delivery through the real nori.alerts path (sops channel
     decryption + stub receiver)
   • RuntimeDirectory preservation, without which the early warning would
     re-alert on every poll
   • with-lock refusing a second owner with 75
   • bounded maintenance running against the real volume and refusing on
     scarce workspace instead of escalating
   • delivery failure failing the unit (fail closed)

  Doesn't test either timer's schedule — that's nixpkgs + systemd's job and
  already exercised by Phase 3's heartbeat.timer.

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
        ../src/infra/common/nixos/inventory.nix
        ../src/infra/common/nixos/service-hardening.nix
        ../src/infra/common/nixos/storage
        ../src/infra/common/nixos/backup.nix
        ../src/services/disk-alert/nixos.nix
        ../src/services/ntfy/nixos/notify.nix
      ];

      environment.etc."sops-test-age.txt".source = ./keys/test-age.txt;
      sops.age.keyFile = "/etc/sops-test-age.txt";
      sops.age.sshKeyPaths = lib.mkForce [ ];
      sops.defaultSopsFile = ./secrets/test.yaml;
      sops.secrets.restic-password = { };

      networking.hostName = "pi";

      nori.inventory = {
        currentHost = "pi";
        hosts = {
          pi = {
            kind = "nixos";
            tags = [ "network-appliance" ];
            profiles = [ ];
            workloads = [ ];
            tailnetIp = "100.0.0.1";
            lanIp = "10.0.0.10";
            role = "appliance";
            roleOneLiner = "";
            codename = "test-pi";
            hardware = "test-qemu";
            primaryJob = "disk-alert";
          };
          workstation = {
            kind = "nixos";
            tags = [ "workhorse" ];
            profiles = [ ];
            workloads = [ ];
            tailnetIp = "100.0.0.2";
            lanIp = "10.0.0.20";
            role = "workhorse";
            roleOneLiner = "test";
            codename = "test-station";
            hardware = "test-qemu";
            primaryJob = "—";
          };
        };
      };

      nori.backupTargets.test-stub = {
        repository = "sftp:stub@stub.test:/stub";
        description = "test stub";
      };

      # A real disposable btrfs volume is the alarm's subject. The ordinary
      # threshold keeps its production default (95), so an alert about this
      # volume can only come from the metadata/expansion-workspace
      # classification. The metadata thresholds are test-local so a freshly
      # created small filesystem classifies immediately: any nonzero metadata
      # usage, with physical workspace far below the 2 GiB critical workspace.
      virtualisation.emptyDiskImages = [ 256 ];
      environment.systemPackages = [ pkgs.btrfs-progs ];

      nori.observability.diskAlert = {
        mountpoints = [ "/mnt/nori-pressure-test" ];
      };
      nori.storagePressure = {
        metadataWarningPct = 1;
        metadataCriticalPct = 1;
      };
      # ntfy-notify owns the sops.secrets.ntfy-channel declaration AND the
      # infra channel that disk-alert now delivers through (nori.alerts);
      # its baseUrl knob redirects delivery → stub receiver.
      nori.observability.ntfyNotify.baseUrl = "http://127.0.0.1:9999";
      nori.observability.ntfyNotify.sopsFile = ./secrets/test.yaml;
      nori.observability.ntfyNotify.secretOwner = "root";

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
    import json

    start_all()
    pi.wait_for_unit("multi-user.target")
    pi.wait_for_unit("test-ntfy-receiver.service")

    with subtest("the packaged CLI measures the real VM filesystem and never reports an error as healthy"):
        meas = json.loads(pi.succeed("nori-storage-pressure probe /"))
        assert set(meas) == {
            "path", "fs_type", "fs_uuid", "ordinary_used_pct",
            "metadata_used_bytes", "metadata_total_bytes",
            "metadata_used_pct", "unallocated_bytes", "state",
        }, f"unexpected measurement shape: {meas!r}"
        assert meas["fs_type"] != "btrfs", (
            f"VM root is btrfs, which the non-btrfs assertions below contradict: {meas!r}"
        )
        assert meas["metadata_used_pct"] is None and meas["unallocated_bytes"] is None, meas
        assert meas["fs_uuid"] is None, meas
        # A measurement error is an error, not a healthy filesystem.
        pi.succeed("nori-storage-pressure check /nonexistent-mnt >/dev/null 2>&1; [ $? -eq 1 ]")
        pi.succeed("test -z \"$(nori-storage-pressure probe /nonexistent-mnt 2>/dev/null)\"")

    with subtest("a real disposable btrfs volume alerts from metadata pressure alone"):
        # The VM gets one blank disk; format and mount it for the alarm.
        disk = pi.succeed(
            "lsblk -dno NAME,TYPE | awk '$2 == \"disk\" && $1 != \"vda\" { print $1; exit }'"
        ).strip()
        assert disk, "no spare disk device found for the btrfs volume"
        pi.succeed(f"mkfs.btrfs -f /dev/{disk}")
        pi.succeed("mkdir -p /mnt/nori-pressure-test")
        pi.succeed(f"mount -t btrfs /dev/{disk} /mnt/nori-pressure-test")

        # A fresh metadata chunk starts nearly empty, so drive real metadata
        # pressure until the production classifier trips (bounded: 20 batches
        # of 500 files). This is the pressure the alarm exists to catch, on a
        # real filesystem measured by the real parser.
        def measure():
            return json.loads(pi.succeed("nori-storage-pressure probe /mnt/nori-pressure-test"))

        for batch in range(20):
            if measure()["state"] == "critical":
                break
            pi.succeed(
                "for i in $(seq 1 500); do echo x > /mnt/nori-pressure-test/f"
                f"{batch * 500 + i}; done"
            )

        meas = measure()
        assert meas["fs_type"] == "btrfs", meas
        assert meas["fs_uuid"], meas
        assert meas["state"] == "critical", (
            f"real btrfs volume never reached metadata critical: {meas!r}"
        )
        # The ordinary threshold is the production 95, so this volume's alert
        # cannot come from ordinary usage — only from metadata pressure with
        # scarce expansion workspace.
        assert meas["ordinary_used_pct"] < 95, meas
        assert meas["metadata_used_pct"] >= 1, meas
        assert meas["unallocated_bytes"] < 2 * 1024 ** 3, meas

        pi.succeed("systemctl start disk-alert.service")
        captured = pi.succeed("cat /var/lib/test-ntfy/messages")

        assert "PATH=/test-channel" in captured, (
            f"alert posted to wrong path: {captured!r}"
        )
        assert "disk critical (/mnt/nori-pressure-test" in captured, (
            f"title missing the btrfs mountpoint: {captured!r}"
        )
        assert "HDR Priority: urgent" in captured, (
            f"missing Priority: urgent: {captured!r}"
        )
        # The body must carry the real measured allocation numbers, not a
        # summary an operator has to re-derive.
        assert "btrfs metadata" in captured, (
            f"body missing the btrfs metadata measurements: {captured!r}"
        )
        assert str(meas["metadata_used_bytes"]) in captured, (
            f"body missing metadata_used_bytes {meas['metadata_used_bytes']}: {captured!r}"
        )
        assert str(meas["unallocated_bytes"]) in captured, (
            f"body missing unallocated_bytes {meas['unallocated_bytes']}: {captured!r}"
        )
        assert "storage-full.md" in captured, (
            f"body missing runbook reference: {captured!r}"
        )

    with subtest("the warning stamp survives a oneshot run"):
        # With the production ordinary threshold and a fresh volume the
        # classification is critical, so no warning fires here; what this
        # asserts is the wiring that makes a once-per-episode warning
        # possible at all — the unit's runtime directory, where the warning
        # stamps live, is preserved across oneshot exits. The stamp semantics
        # themselves (warn once, no repeat, recovery re-arms, a failed
        # delivery is not marked notified) are covered by
        # src/infra/common/nixos/storage/pressure.test.sh, which drives the
        # same pressure-alarm.bash the unit executes.
        assert pi.succeed(
            "systemctl show -p RuntimeDirectoryPreserve --value disk-alert.service"
        ).strip() == "yes"
        pi.succeed("test -d /run/disk-alert")

    with subtest("with-lock refuses a second owner"):
        out = pi.succeed(
            "nori-storage-pressure with-lock / sleep 3 >/dev/null 2>&1 & sleep 1; "
            "nori-storage-pressure with-lock / true; echo rc=$?"
        )
        assert "rc=75" in out, f"expected 75 from the second owner: {out!r}"

    with subtest("bounded maintenance runs against the real btrfs volume and refuses on scarce workspace"):
        # The volume's physical workspace is far below the 2 GiB critical
        # workspace, so the run must reclaim empty block groups (a real
        # `btrfs balance start -dusage=0,limit=4`) and then refuse further
        # compaction with an actionable error instead of escalating.
        pi.fail("systemctl start nori-storage-pressure-maintain.service")
        journal = pi.succeed("journalctl -u nori-storage-pressure-maintain.service")
        assert "refusing further compaction" in journal, (
            f"maintenance did not refuse on scarce workspace: {journal!r}"
        )

    with subtest("disk-alert fails closed when notification delivery fails"):
        pi.succeed("systemctl stop test-ntfy-receiver.service")
        pi.fail("systemctl start disk-alert.service")
        assert pi.succeed("systemctl is-failed disk-alert.service").strip() == "failed"
  '';
}
