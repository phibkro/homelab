/**
  Restic backup roundtrip — workstation alone, local repo, end-to-end.

  Backups are the homelab's only catastrophic-silent-failure surface:
  if a `nori.backups.<X>` unit silently stops snapshotting (sops
  password lost, ExecStart drifted, prepareCommand wedged, target
  unreachable), nothing notices until restore day. test-backups
  (Layer 3) catches stale-snapshot drift on the LIVE pi; this Layer 2
  catches whether the unit's RUN works at all.

  Scenario:
   - One workstation-shaped node (role=workhorse so it can legally
     have a LOCAL target — appliance hosts can't, per the placement
     assertion in src/infra/common/nixos/backup.nix).
   - A local restic target at /var/lib/test-restic-repo.
   - A real `nori.backups.testjob.include = [ "/var/lib/test-source" ]`
     declaration.
   - Pre-seed /var/lib/test-source/marker.txt with a known string.
   - testScript fires the generated restic-backups-testjob-onetouch
     unit, waits for completion, then uses restic itself to verify
     the snapshot exists AND contains the marker file. End-to-end.

  Composition exercised:
   - sops-nix decrypts restic-password
   - backup module fans out (job, target) → systemd unit
   - restic.nix's environment setup (RESTIC_PASSWORD_FILE)
   - restic init + backup against a local repo
   - Snapshot listing + restore-style retrieval

  Invoked via `nix build .#checks.<system>.e2e-restic-backup`.
*/
{
  pkgs,
  lib,
  inputs,
  ...
}:

pkgs.testers.runNixOSTest {
  name = "e2e-restic-backup";

  node.specialArgs = { inherit inputs; };

  nodes.workstation =
    { config, lib, ... }:
    {
      imports = [
        inputs.sops-nix.nixosModules.sops
        ../src/infra/common/nixos/inventory.nix
        ../src/infra/common/nixos/service-hardening.nix
        ../src/infra/common/nixos/storage
        ../src/infra/common/nixos/backup.nix
        ../src/services/restic-backup/nixos.nix
        ../src/services/restic-target/nixos.nix
      ];

      environment.etc."sops-test-age.txt".source = ./keys/test-age.txt;
      sops.age.keyFile = "/etc/sops-test-age.txt";
      sops.age.sshKeyPaths = lib.mkForce [ ];
      sops.defaultSopsFile = ./secrets/test.yaml;
      sops.secrets.restic-password = { };

      networking.hostName = "workstation";

      # Synthetic compiler projection: workstation is the workhorse, which
      # permits local restic targets. Appliance hosts cannot own local repos.
      nori.inventory.currentHost = "workstation";
      nori.inventory.hosts = {
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
          primaryJob = "—";
        };
        workstation = {
          kind = "nixos";
          tags = [ "workhorse" ];
          profiles = [ ];
          workloads = [ ];
          tailnetIp = "100.0.0.2";
          lanIp = "10.0.0.20";
          role = "workhorse";
          roleOneLiner = "test workhorse";
          codename = "test-station";
          hardware = "test-qemu";
          primaryJob = "backup roundtrip";
        };
      };

      # A real mounted filesystem exercises the production mount guard.
      nori.inventory.backup =
        let
          backup = import ../src/inventory/backup.nix { };
        in
        backup
        // {
          enabled = true;
          targetName = "onetouch";
          mountPoint = "/var/lib/test-restic-repo";
          pi = backup.pi // {
            authorizedKey = lib.removeSuffix "\n" (builtins.readFile ./keys/restic-test.pub);
          };
        };
      services.openssh.enable = true;
      environment.etc."restic-test-key" = {
        source = ./keys/restic-test;
        mode = "0600";
      };
      virtualisation.fileSystems."/var/lib/test-restic-repo" = {
        device = "tmpfs";
        fsType = "tmpfs";
      };

      # Real backup job — same shape every prod service declares.
      # Pin to the onetouch target so we don't also try the
      # nonexistent prod targets.
      nori.backups.testjob = {
        include = [ "/var/lib/test-source" ];
        targets = [ "onetouch" ];
      };

      # Pre-seed the source data so the snapshot has something
      # non-trivial. The testScript greps for this marker after
      # restore to prove the round-trip. Also pre-create the
      # restic repo's parent directory — restic's `initialize=true`
      # lazily creates the per-job subdir + `init`s the repo, but
      # the parent must already exist (this is what nori.fs
      # normally handles for prod paths).
      systemd.tmpfiles.rules = [
        "d /var/lib/test-source 0755 root root -"
        "f /var/lib/test-source/marker.txt 0644 root root - hello-from-test-marker"
        "d /var/lib/test-restic-repo 0700 root root -"
      ];

      nixpkgs.config = lib.mkForce {
        allowAliases = true;
        allowBroken = false;
        allowUnfree = false;
      };
      documentation.enable = lib.mkForce false;

      # `restic` binary on PATH so the testScript can list snapshots
      # via the same CLI an operator would use.
      environment.systemPackages = [ pkgs.restic ];
    };

  testScript = ''
    import shlex
    start_all()
    workstation.wait_for_unit("multi-user.target")

    with subtest("sops planted restic-password"):
        # Sanity: the unit's RESTIC_PASSWORD_FILE points at this path.
        # If sops didn't decrypt, the unit would fail at startup with a
        # less specific error, so an explicit check disambiguates.
        workstation.succeed("test -s /run/secrets/restic-password")

    with subtest("backup unit runs successfully against local repo"):
        # The fanout name is restic-backups-<job>-<target>.service.
        # initialize=true on a fresh target creates the repo lazily.
        workstation.succeed(
            "systemctl start restic-backups-testjob-onetouch.service"
        )
        # Wait for the oneshot to leave activating state.
        workstation.wait_until_succeeds(
            "systemctl is-active restic-backups-testjob-onetouch.service "
            "|| systemctl show -p Result restic-backups-testjob-onetouch.service "
            "| grep -q success",
            timeout=60,
        )
        result = workstation.succeed(
            "systemctl show -p Result --value restic-backups-testjob-onetouch.service"
        ).strip()
        assert result == "success", f"backup unit Result={result!r}"

    with subtest("snapshot landed in the repo + contains the marker file"):
        # Use restic directly — the same path an operator would
        # take to verify a restore. Exercises the password file +
        # repo location at the same time.
        # Each (job, target) lands in <target.repository>/<jobName>
        # — the fanout shape from src/infra/common/nixos/backup.nix.
        env = (
            "RESTIC_PASSWORD_FILE=/run/secrets/restic-password "
            "RESTIC_REPOSITORY=/var/lib/test-restic-repo/testjob "
        )

        # At least one snapshot exists.
        snaps = workstation.succeed(f"{env} restic snapshots --json")
        assert '"paths"' in snaps, f"no snapshots in repo: {snaps!r}"
        assert "/var/lib/test-source" in snaps, (
            f"snapshot didn't include /var/lib/test-source: {snaps!r}"
        )

        # The marker file landed inside it.
        ls = workstation.succeed(f"{env} restic ls latest")
        assert "/var/lib/test-source/marker.txt" in ls, (
            f"marker.txt missing from snapshot: {ls!r}"
        )
        workstation.succeed(f"{env} restic restore latest --target /tmp/restore")
        workstation.succeed("cmp /var/lib/test-source/marker.txt /tmp/restore/var/lib/test-source/marker.txt")

    with subtest("Pi transport backs up and restores through the production SFTP jail"):
        workstation.wait_for_unit("sshd.service")
        workstation.succeed("systemctl start restic-target-directories.service")
        assert workstation.succeed("systemctl show -p Result --value restic-target-directories.service").strip() == "success"
        workstation.succeed("awk '{print \"localhost \" $1 \" \" $2}' /etc/ssh/ssh_host_ed25519_key.pub > /tmp/restic-known-hosts")
        transport = "ssh -i /etc/restic-test-key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/tmp/restic-known-hosts restic@localhost -s sftp"
        remote = f"RESTIC_PASSWORD_FILE=/run/secrets/restic-password restic -o sftp.connections=1 -o 'sftp.command={transport}' -r sftp:restic@localhost:/pihole"
        workstation.succeed(f"{remote} init </dev/null")
        workstation.succeed(f"{remote} backup /var/lib/test-source </dev/null")
        workstation.succeed(f"{remote} restore latest --target /tmp/pi-restore </dev/null")
        workstation.succeed("cmp /var/lib/test-source/marker.txt /tmp/pi-restore/var/lib/test-source/marker.txt")
        sftp = "sftp -b - -i /etc/restic-test-key -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/tmp/restic-known-hosts restic@localhost"
        workstation.fail(f"echo 'get /../../testjob/config /tmp/escaped' | {sftp}")
        workstation.execute("timeout 5 ssh -i /etc/restic-test-key -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/tmp/restic-known-hosts restic@localhost 'touch /tmp/shell-escaped' </dev/null")
        workstation.succeed("test ! -e /tmp/shell-escaped")
        workstation.succeed("test ! -e /tmp/escaped")

    with subtest("missing backup mount cannot write onto root filesystem"):
        workstation.succeed("systemctl stop $(systemd-escape --path --suffix=mount /var/lib/test-restic-repo)")
        workstation.succeed("systemctl mask --runtime $(systemd-escape --path --suffix=mount /var/lib/test-restic-repo)")
        workstation.fail("systemctl start restic-backups-testjob-onetouch.service")
        workstation.succeed("test ! -e /var/lib/test-restic-repo/testjob")
        # Match production's systemd execution boundary. An early SSH failure
        # must not inherit and disrupt the test driver's control terminal.
        status, output = workstation.execute("systemd-run --wait --pipe --collect --setenv=PATH=/run/current-system/sw/bin /bin/sh -c " + shlex.quote(remote + " snapshots 2>&1"))
        assert status != 0 and "unable to start the sftp session" in output, output
  '';
}
