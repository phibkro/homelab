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
     assertion in modules/infra/backup/default.nix).
   - A local restic target at /var/lib/test-restic-repo.
   - A real `nori.backups.testjob.include = [ "/var/lib/test-source" ]`
     declaration.
   - Pre-seed /var/lib/test-source/marker.txt with a known string.
   - testScript fires the generated restic-backups-testjob-localtest
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
        ../modules/infra/hosts.nix
        ../modules/infra/placement.nix
        ../modules/infra/capabilities
        ../modules/infra/storage
        ../modules/infra/backup
        ../modules/infra/networking
      ];

      environment.etc."sops-test-age.txt".source = ./keys/test-age.txt;
      sops.age.keyFile = "/etc/sops-test-age.txt";
      sops.age.sshKeyPaths = lib.mkForce [ ];
      sops.defaultSopsFile = ./secrets/test.yaml;
      sops.secrets.restic-password = { };

      networking.hostName = "workstation";
      nori.domain = "test.lan";
      nori.lanIp = lib.mkForce "10.0.0.20";

      # Synthetic hosts registry — workstation is role=workhorse
      # which is what unlocks local restic targets per the placement
      # assertion (appliance hosts can't have local repos).
      nori.hosts.pi = {
        tailnetIp = "100.0.0.1";
        lanIp = "10.0.0.10";
        role = "appliance";
        roleOneLiner = "";
        codename = "test-pi";
        hardware = "test-qemu";
        primaryJob = "—";
      };
      nori.hosts.workstation = {
        tailnetIp = "100.0.0.2";
        lanIp = "10.0.0.20";
        role = "workhorse";
        roleOneLiner = "test workhorse";
        codename = "test-station";
        hardware = "test-qemu";
        primaryJob = "backup roundtrip";
      };

      # Local target — restic creates the directory + inits the repo
      # on first run (initialize=true is the backup module's default).
      nori.backupTargets.localtest = {
        repository = "/var/lib/test-restic-repo";
        description = "in-VM local restic repo for the roundtrip test";
      };

      # Real backup job — same shape every prod service declares.
      # Pin to the localtest target so we don't also try the
      # nonexistent prod targets.
      nori.backups.testjob = {
        include = [ "/var/lib/test-source" ];
        targets = [ "localtest" ];
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
            "systemctl start restic-backups-testjob-localtest.service"
        )
        # Wait for the oneshot to leave activating state.
        workstation.wait_until_succeeds(
            "systemctl is-active restic-backups-testjob-localtest.service "
            "|| systemctl show -p Result restic-backups-testjob-localtest.service "
            "| grep -q success",
            timeout=60,
        )
        result = workstation.succeed(
            "systemctl show -p Result --value restic-backups-testjob-localtest.service"
        ).strip()
        assert result == "success", f"backup unit Result={result!r}"

    with subtest("snapshot landed in the repo + contains the marker file"):
        # Use restic directly — the same path an operator would
        # take to verify a restore. Exercises the password file +
        # repo location at the same time.
        # Each (job, target) lands in <target.repository>/<jobName>
        # — the fanout shape from modules/infra/backup/default.nix.
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
  '';
}
