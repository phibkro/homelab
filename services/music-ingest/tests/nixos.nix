/**
  Disposable Gate-D acceptance for the direct music-ingest NixOS module.

  The test imports the direct module and starts its real unit in
  a NixOS guest.  The two tmpfs mounts are deliberate: staging and inflight
  are directories on one device, while master is a separate device.  Nothing
  here uses a production media mount or notification endpoint.

  The direct module API exercised by this fixture is:

    nori.services."music-ingest" = {
      resources = {
        staging = { path = "/mnt/music-ingest/staging-fs/staging"; filesystem = "staging-fs"; };
        inflight = { path = "/mnt/music-ingest/staging-fs/.music-ingest-inflight"; filesystem = "staging-fs"; };
        master = { path = "/mnt/music-ingest/master-fs/music"; filesystem = "master-fs"; };
      };
      stabilitySeconds = 60;
      interval = "1h";
    };

  This file owns only the disposable guest and its observations.
*/
{
  pkgs,
  lib,
  ...
}:

pkgs.testers.runNixOSTest {
  name = "music-ingest-direct-vm";

  nodes.music =
    { config, ... }:
    {
      imports = [
        ../nixos.nix
        ../../../infra/common/nixos/service-hardening.nix
        ../../../infra/common/nixos/backup.nix
      ];

      networking.hostName = "music-ingest-vm";
      documentation.enable = lib.mkForce false;

      # The direct service grants this group to its service principal.  The
      # test makes the ownership observable by keeping the mounted trees
      # root:media with setgid directories.
      users.groups.media = { };

      nori.services."music-ingest" = {
        resources = {
          staging = {
            path = "/mnt/music-ingest/staging-fs/staging";
            filesystem = "staging-fs";
          };
          inflight = {
            path = "/mnt/music-ingest/staging-fs/.music-ingest-inflight";
            filesystem = "staging-fs";
          };
          master = {
            path = "/mnt/music-ingest/master-fs/music";
            filesystem = "master-fs";
          };
        };
        stabilitySeconds = 60;
        interval = "1h";
      };

      # One tmpfs contains both the source and durable claim directories, so a
      # claim rename is on one filesystem.  Master deliberately has a second
      # tmpfs: verified copy crosses the device boundary and publication is an
      # atomic rename on the master device.
      virtualisation.fileSystems."/mnt/music-ingest/staging-fs" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=0755" ];
      };
      virtualisation.fileSystems."/mnt/music-ingest/master-fs" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=0755" ];
      };

      systemd.tmpfiles.rules = [
        # The direct module owns the three data-tree tmpfiles rules.  This
        # fixture adds only the local observer's marker directory.
        "d /run/music-ingest-notify 0755 root root - -"
      ];

      # The direct relation is observed through this fixture-local
      # template.  It records activation only; it does not perform an HTTP
      # request and cannot stand in for external alert delivery.
      systemd.services."notify@" = {
        description = "Fixture-local music-ingest failure observer";
        script = ''
          printf '%s\n' activated >> /run/music-ingest-notify/activated
        '';
        serviceConfig = {
          Type = "oneshot";
        };
      };

    };

  testScript = ''
    STAGING = "/mnt/music-ingest/staging-fs/staging"
    INFLIGHT = "/mnt/music-ingest/staging-fs/.music-ingest-inflight"
    MASTER = "/mnt/music-ingest/master-fs/music"
    NOTIFY = "/run/music-ingest-notify/activated"
    UNIT = "music-ingest.service"

    def shell_quote(value):
        # testScript runs in the host Python process, while command strings
        # execute in the guest.  Inputs below are constants, but quoting keeps
        # the helper honest if a fixture path changes later.
        import shlex
        return shlex.quote(value)

    def write_file(machine, path, contents, age=True):
        parent = machine.succeed("dirname " + shell_quote(path)).strip()
        machine.succeed(
            "install -d -m 2775 -o root -g media " + shell_quote(parent)
        )
        machine.succeed(
            "printf %s "
            + shell_quote(contents)
            + " > "
            + shell_quote(path)
            + " && chmod 0664 "
            + shell_quote(path)
        )
        if age:
            machine.succeed("touch -d '2 hours ago' " + shell_quote(path))

    def reset_service(machine):
        machine.succeed("systemctl reset-failed " + UNIT + " || true")

    def service_result(machine):
        return machine.succeed(
            "systemctl show -p Result --value " + UNIT
        ).strip()

    def service_status(machine):
        return int(
            machine.succeed(
                "systemctl show -p ExecMainStatus --value " + UNIT
            ).strip()
        )

    start_all()
    music.wait_for_unit("multi-user.target")

    with subtest("direct unit and timer are loaded with real hardening"):
        music.wait_for_unit("music-ingest.timer")
        timer = music.succeed(
            "systemctl show music-ingest.timer "
            "-p UnitFileState -p ActiveState "
            "-p NextElapseUSecMonotonic -p NextElapseUSecRealtime"
        )
        assert "UnitFileState=enabled" in timer, timer
        assert "ActiveState=active" in timer, timer
        next_monotonic = music.succeed(
            "systemctl show -p NextElapseUSecMonotonic --value "
            "music-ingest.timer"
        ).strip()
        # module cadence uses OnBootSec/OnUnitActiveSec, so the
        # realtime property is legitimately n/a; the monotonic deadline is
        # the scheduled timer evidence.
        assert next_monotonic and next_monotonic != "n/a", (timer, next_monotonic)

        props = music.succeed(
            "systemctl show "
            + UNIT
            + " -p User -p Group -p SupplementaryGroups -p UMask "
            "-p ExecStart -p BindPaths -p NoNewPrivileges "
            "-p ProtectSystem -p ProtectHome -p PrivateDevices "
            "-p PrivateTmp -p OnFailure"
        )
        assert "User=music-ingest" in props, props
        assert "Group=music-ingest" in props, props
        assert "SupplementaryGroups=media" in props, props
        assert "UMask=0002" in props, props
        assert "/nix/store/" in props and "music-ingest" in props, props
        assert STAGING in props and INFLIGHT in props and MASTER in props, props
        assert "NoNewPrivileges=yes" in props, props
        assert "ProtectSystem=strict" in props, props
        assert "ProtectHome=yes" in props, props
        assert "PrivateDevices=yes" in props, props
        assert "PrivateTmp=yes" in props, props
        assert "OnFailure=notify@music-ingest.service" in props, props

        mounts = music.succeed(
            "systemctl is-active "
            "$(systemd-escape --path --suffix=mount /mnt/music-ingest/staging-fs) "
            "$(systemd-escape --path --suffix=mount /mnt/music-ingest/master-fs)"
        )
        assert mounts.count("active") == 2, mounts
        devices = music.succeed(
            "stat -c '%d' " + shell_quote(STAGING) + " "
            + shell_quote(INFLIGHT) + " " + shell_quote(MASTER)
        ).splitlines()
        assert len(devices) == 3 and devices[0] == devices[1] and devices[0] != devices[2], devices

    with subtest("manual direct service publishes bytes with owner group and mode"):
        track = STAGING + "/Artist/Album/Stable.FLAC"
        write_file(music, track, "stable-flac-bytes")
        reset_service(music)
        music.succeed("systemctl start " + UNIT)
        music.wait_until_succeeds(
            "test \"$(systemctl show -p Result --value "
            + UNIT
            + ")\" = success",
            timeout=30,
        )
        published = MASTER + "/Artist/Album/Stable.FLAC"
        assert music.succeed("cat " + shell_quote(published)).strip() == "stable-flac-bytes"
        owner = music.succeed(
            "stat -c '%U:%G:%a' " + shell_quote(published)
        ).strip()
        assert owner == "music-ingest:media:664", owner
        music.succeed("test ! -e " + shell_quote(track))
        music.succeed("test ! -e " + shell_quote(INFLIGHT + "/Artist/Album/Stable.FLAC"))
        assert service_result(music) == "success"
        assert service_status(music) == 0

    with subtest("pre-existing claim under hidden inflight root is recovered"):
        claim = INFLIGHT + "/Recovered/Album/Track.FLAC"
        write_file(music, claim, "recovered-claim")
        reset_service(music)
        music.succeed("systemctl start " + UNIT)
        music.wait_until_succeeds(
            "test \"$(systemctl show -p Result --value "
            + UNIT
            + ")\" = success",
            timeout=30,
        )
        published = MASTER + "/Recovered/Album/Track.FLAC"
        assert music.succeed("cat " + shell_quote(published)).strip() == "recovered-claim"
        music.succeed("test ! -e " + shell_quote(claim))
        assert service_status(music) == 0

    with subtest("identical publication is idempotent and removes only the owned source"):
        duplicate = STAGING + "/Artist/Album/Stable.FLAC"
        write_file(music, duplicate, "stable-flac-bytes")
        before = music.succeed("sha256sum " + shell_quote(MASTER + "/Artist/Album/Stable.FLAC"))
        reset_service(music)
        music.succeed("systemctl start " + UNIT)
        music.wait_until_succeeds(
            "test \"$(systemctl show -p Result --value "
            + UNIT
            + ")\" = success",
            timeout=30,
        )
        after = music.succeed("sha256sum " + shell_quote(MASTER + "/Artist/Album/Stable.FLAC"))
        assert before == after, (before, after)
        music.succeed("test ! -e " + shell_quote(duplicate))
        assert service_status(music) == 0

    with subtest("operator conflict returns exit 3, preserves master and activates observer"):
        conflict = STAGING + "/Artist/Album/Conflict.FLAC"
        destination = MASTER + "/Artist/Album/Conflict.FLAC"
        write_file(music, destination, "master-bytes")
        write_file(music, conflict, "staging-bytes")
        reset_service(music)
        music.fail("systemctl start " + UNIT)
        music.wait_until_succeeds(
            "test \"$(systemctl show -p Result --value "
            + UNIT
            + ")\" = exit-code",
            timeout=30,
        )
        assert service_result(music) == "exit-code"
        assert service_status(music) == 3
        assert music.succeed("cat " + shell_quote(destination)).strip() == "master-bytes"
        quarantined = STAGING + "/.conflicts/Artist/Album/Conflict.FLAC"
        music.succeed("test -f " + shell_quote(quarantined))
        music.succeed("test ! -e " + shell_quote(conflict))
        music.wait_until_succeeds(
            "test -s " + shell_quote(NOTIFY) + " && "
            "grep -qx activated " + shell_quote(NOTIFY),
            timeout=30,
        )

    with subtest("permission traversal failure is a failed systemd result"):
        blocked = STAGING + "/Blocked"
        music.succeed("install -d -m 0700 -o root -g root " + shell_quote(blocked))
        write_file(music, blocked + "/unreadable.flac", "cannot-traverse")
        # The helper creates a group-writable parent for normal fixtures;
        # restore the root-only traversal boundary for this negative case.
        music.succeed("chmod 0700 " + shell_quote(blocked))
        reset_service(music)
        music.fail("systemctl start " + UNIT)
        music.wait_until_succeeds(
            "test \"$(systemctl show -p Result --value "
            + UNIT
            + ")\" = exit-code",
            timeout=30,
        )
        assert service_result(music) == "exit-code"
        assert service_status(music) != 0
        music.succeed("test -f " + shell_quote(blocked + "/unreadable.flac"))
        music.succeed("rm -rf " + shell_quote(blocked))
  '';
}
