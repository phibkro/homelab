/*
  Pressure-safe snapshot policy — see
  docs/specs/2026-10-07-storage-pressure.md § "Snapshot policy".

  Two layers in one file:

  1. Unit wiring (evaluated): every btrbk instance's ExecStart is the
     pressure guard, carrying that instance's own config, command and
     touched paths; the unit requires the real source and target mounts
     (not a parent directory that may sit on another filesystem); no
     ExecCondition exists that could report a skipped snapshot as a
     successful backup; User/Group/OnFailure survive the wrapper.

  2. Business behaviour (built): the real generated guard script runs
     against a disposable fixture that replaces only the two external
     commands it consumes — `nori-storage-pressure` (implementing the
     documented check/with-lock contract, including the measurement
     JSON) and `btrbk` (recording its argv). The assertions are about
     outcomes — exit status, which btrbk operation ran, how many
     filesystems were locked and in what order — not about log text.
*/
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  config = inputs.self.nixosConfigurations.workstation.config;

  instances = config.services.btrbk.instances;
  instanceNames = lib.attrNames instances;

  unitOf = name: config.systemd.services."btrbk-${name}";
  execStartOf = name: (unitOf name).serviceConfig.ExecStart;
  guardExe =
    if instanceNames == [ ] then
      throw "no btrbk instances to check: the snapshot policy test expects the workstation's snapshot instances"
    else
      lib.head (lib.splitString " " (execStartOf (lib.head instanceNames)));

  confOf = name: "/etc/btrbk/${name}.conf";
  commandOf = name: if instances.${name}.snapshotOnly then "snapshot" else "run";

  # The paths the guard must be given, read from the instance's own settings.
  configuredPathsOf =
    name:
    let
      settings = instances.${name}.settings;
      join =
        base: rel:
        if lib.hasPrefix "/" rel then
          rel
        else if base == "/" then
          "/${rel}"
        else
          "${base}/${rel}";
    in
    lib.unique (
      lib.concatLists (
        lib.mapAttrsToList (
          volume: vcfg:
          let
            subvolumes = vcfg.subvolume or { };
          in
          map (sub: join volume sub) (lib.attrNames subvolumes)
          ++ [ (join volume settings.snapshot_dir) ]
          ++ lib.attrNames (vcfg.target or { })
        ) settings.volume
      )
    );

  instancesOk = lib.elem "root" instanceNames && lib.elem "media" instanceNames;

  # Targets declared on a volume section: the receive directories the run
  # writes into, and therefore filesystems the guard must cover.
  targetPathsOf =
    name:
    lib.unique (
      lib.concatLists (
        lib.mapAttrsToList (_: vcfg: lib.attrNames (vcfg.target or { })) instances.${name}.settings.volume
      )
    );

  # Independent cross-check for the media instance: the filesystem registry
  # says which /mnt/media entries are snapshot-worthy, so the guard must be
  # given those paths — and not /mnt/media itself, which is a directory on the
  # root filesystem.
  registryMediaPaths = map (f: f.path) (
    lib.filter (f: lib.hasPrefix "/mnt/media/" f.path && f.tier != "re-derivable") (
      lib.attrValues config.nori.fs
    )
  );
  ironwolfSnapshotMount = "/mnt/media/.snapshots";

  # ExecStart is exactly the guard plus this instance's config, command and
  # touched paths; and no instance may carry an ExecCondition that reports a
  # skipped snapshot as a successful backup.
  execStartOk = lib.all (
    name:
    execStartOf name == lib.escapeShellArgs (
      [
        guardExe
        (confOf name)
        (commandOf name)
      ]
      ++ configuredPathsOf name
    )
  ) instanceNames;
  noExecCondition = lib.all (name: !((unitOf name).serviceConfig ? ExecCondition)) instanceNames;

  # The filesystem-ownership facts the guard exists for: the root instance
  # receives into the IronWolf, so that mount must be required and locked; the
  # media instance's subvolumes are IronWolf subvolumes even though
  # /mnt/media is on the root filesystem.
  rootPaths = configuredPathsOf "root";
  mediaPaths = configuredPathsOf "media";
  ownershipOk =
    lib.all (p: lib.elem p rootPaths) [
      "/home"
      "/srv/nori"
      "/srv/share"
      "/var/lib"
      "/.snapshots"
    ]
    && lib.all (p: lib.elem p rootPaths) (targetPathsOf "root")
    && lib.all (p: lib.elem p mediaPaths) registryMediaPaths
    && lib.elem ironwolfSnapshotMount mediaPaths
    && !(lib.elem "/mnt/media" mediaPaths)
    && lib.all (
      name: (unitOf name).unitConfig.RequiresMountsFor == configuredPathsOf name
    ) instanceNames;

  # The guard, not a silently-skipped condition, decides the unit's fate.
  unitIntentOk = lib.all (
    name:
    let
      unit = unitOf name;
    in
    unit.serviceConfig.User == "btrbk"
    && unit.serviceConfig.Group == "btrbk"
    && lib.elem "notify@btrbk-${name}.service" unit.unitConfig.OnFailure
  ) instanceNames;

  # The guard resolves nori-storage-pressure and btrbk from the unit PATH;
  # asserting it here keeps the substitution seam and the production wiring
  # the same fact.
  pathOk = lib.all (
    name:
    let
      inherit (unitOf name) path;
    in
    lib.any (p: toString p == toString config.nori.storagePressure.package) path
    && lib.any (p: toString p == toString pkgs.btrbk) path
  ) instanceNames;

  lockOk =
    config.nori.storagePressure.lockGroup == "btrbk"
    && lib.elem "btrbk" (config.users.users.btrbk.extraGroups or [ ]);

  # nori-storage-pressure, reduced to the documented contract: `check` reports
  # the filesystem identity as JSON and exits with the next scripted code;
  # `with-lock` fails 75 when the case marks a filesystem busy and otherwise
  # runs the command it was given.
  pressureFixture = pkgs.writeShellApplication {
    name = "fixture-nori-storage-pressure";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      state=$NORI_SNAPSHOT_FIXTURE_STATE
      case "''${1-}" in
        check)
          path=''${2-}
          printf 'check %s\n' "$path" >> "$state/log"
          entry=$(grep -F -- "$path|" "$state/fsmap" | head -n 1)
          if [ -z "$entry" ]; then
            printf 'fixture-nori-storage-pressure: cannot read filesystem type of %s\n' "$path" >&2
            exit 1
          fi
          fs_type=''${entry#*|}
          fs_type=''${fs_type%%|*}
          fs_uuid=''${entry##*|}
          code=$(head -n 1 "$state/codes")
          if [ "$(wc -l < "$state/codes")" -gt 1 ]; then
            tail -n +2 "$state/codes" > "$state/codes.next"
            mv "$state/codes.next" "$state/codes"
          fi
          state_word=healthy
          if [ "$code" = 75 ]; then
            state_word=critical
          fi
          if [ "$fs_uuid" = none ]; then
            printf '{"path":"%s","fs_type":"%s","fs_uuid":null,"state":"%s"}\n' \
              "$path" "$fs_type" "$state_word"
          else
            printf '{"path":"%s","fs_type":"%s","fs_uuid":"%s","state":"%s"}\n' \
              "$path" "$fs_type" "$fs_uuid" "$state_word"
          fi
          exit "$code"
          ;;
        with-lock)
          printf 'lock %s\n' "''${2-}" >> "$state/log"
          if [ -f "$state/lock-busy" ]; then
            printf 'fixture-nori-storage-pressure: lock busy: %s\n' "''${2-}" >&2
            exit 75
          fi
          shift 2
          exec "$@"
          ;;
        *)
          printf 'fixture-nori-storage-pressure: unexpected subcommand %s\n' "''${1-}" >&2
          exit 64
          ;;
      esac
    '';
  };

  btrbkFixture = pkgs.writeShellApplication {
    name = "fixture-btrbk";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      printf 'btrbk %s\n' "$*" >> "$NORI_SNAPSHOT_FIXTURE_STATE/log"
      exit 0
    '';
  };
in
assert lib.assertMsg instancesOk ''
  the snapshot policy test expects the workstation's root and media snapshot
  instances; found: ${lib.concatStringsSep " " instanceNames}
'';
assert lib.assertMsg execStartOk ''
  every btrbk instance ExecStart must be the pressure guard with that
  instance's own config, command and touched paths:
    ${lib.generators.toPretty { } (lib.mapAttrs (name: _: execStartOf name) instances)}
    expected paths: ${
      lib.generators.toPretty { } (lib.mapAttrs (name: _: configuredPathsOf name) instances)
    }
'';
assert lib.assertMsg noExecCondition ''
  no btrbk unit may carry an ExecCondition that reports a skipped snapshot as
  a successful backup:
    ${lib.generators.toPretty { } (lib.mapAttrs (name: _: (unitOf name).serviceConfig) instances)}
'';
assert lib.assertMsg ownershipOk ''
  the guard must be given every filesystem the instance touches, and the unit
  must require those real source and target mounts:
    root paths: ${lib.generators.toPretty { } rootPaths}
    media paths: ${lib.generators.toPretty { } mediaPaths}
    registry media paths: ${lib.generators.toPretty { } registryMediaPaths}
    RequiresMountsFor: ${
      lib.generators.toPretty { } (
        lib.mapAttrs (name: _: (unitOf name).unitConfig.RequiresMountsFor) instances
      )
    }
'';
assert lib.assertMsg unitIntentOk ''
  the wrapped btrbk units must keep User=btrbk, Group=btrbk and their
  OnFailure → notify@ wiring:
    ${lib.generators.toPretty { } (lib.mapAttrs (name: _: unitOf name) instances)}
'';
assert lib.assertMsg pathOk ''
  each btrbk unit must provide nori-storage-pressure and btrbk on PATH:
    ${lib.generators.toPretty { } (lib.mapAttrs (name: _: (unitOf name).path) instances)}
'';
assert lib.assertMsg lockOk ''
  btrbk must share the allocation lock group with the maintenance worker:
    lockGroup = ${config.nori.storagePressure.lockGroup}
    btrbk groups = ${lib.concatStringsSep " " (config.users.users.btrbk.extraGroups or [ ])}
'';
pkgs.runCommandLocal "eval-snapshot-behavior"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.util-linux
    ];
  }
  ''
    set -euo pipefail
    export HOME=$TMPDIR

    guard=${lib.escapeShellArg guardExe}
    conf=/etc/btrbk/root.conf
    bindir=$TMPDIR/bin
    emptybin=$TMPDIR/empty-bin
    a=$TMPDIR/fs-a
    b=/dev/shm/snapshot-behavior-fs-b
    mkdir -p "$bindir" "$emptybin" "$a" "$b"
    ln -s ${pressureFixture}/bin/fixture-nori-storage-pressure "$bindir/nori-storage-pressure"
    ln -s ${btrbkFixture}/bin/fixture-btrbk "$bindir/btrbk"

    # The guard hands the containing mount to the pressure CLI, so the fixture
    # is keyed by those mounts. Two paths under different sandbox mounts give
    # two distinct filesystems.
    mount_a=$(findmnt --noheadings --output TARGET --target "$a")
    mount_b=$(findmnt --noheadings --output TARGET --target "$b")
    if [ -z "$mount_a" ] || [ -z "$mount_b" ] || [ "$mount_a" = "$mount_b" ]; then
      echo "test fixture cannot find two distinct mounts ($mount_a, $mount_b)" >&2
      exit 1
    fi

    failures=0
    fail() {
      printf 'FAIL: %s\n' "$*" >&2
      failures=$((failures + 1))
    }

    new_case() {
      state=$TMPDIR/case-$1
      rm -rf "$state"
      mkdir -p "$state"
      : > "$state/log"
      export NORI_SNAPSHOT_FIXTURE_STATE=$state
    }

    fsmap() {
      printf '%s\n' "$@" > "$state/fsmap"
    }

    codes() {
      printf '%s\n' "$@" > "$state/codes"
    }

    run_guard() {
      run_status=0
      PATH=$run_path "$guard" "$@" > "$state/out" 2> "$state/err" || run_status=$?
    }

    expect_status() {
      if [ "$1" != "$2" ]; then
        fail "$3: expected exit $1, got $2 (stderr: $(cat "$state/err" 2>/dev/null || true))"
      fi
    }

    count() {
      grep -c -F -- "$1" "$state/log" || true
    }

    first_line() {
      grep -n -F -- "$1" "$state/log" | head -n 1 | cut -d: -f1
    }

    expect_count() {
      actual=$(count "$2")
      if [ "$actual" != "$1" ]; then
        fail "$3: expected $1 × '$2', got $actual (log: $(tr '\n' ';' < "$state/log"))"
      fi
    }

    expect_before() {
      before=$(first_line "$1")
      after=$(first_line "$2")
      if [ -z "$before" ] || [ -z "$after" ] || [ "$before" -ge "$after" ]; then
        fail "$3: '$1' must precede '$2' (log: $(tr '\n' ';' < "$state/log"))"
      fi
    }

    # Healthy pressure: the snapshot runs under the filesystem lock, after a
    # gate check and an in-lock re-check.
    new_case healthy
    fsmap "$mount_a|btrfs|uuid-a"
    codes 0
    run_path=$bindir
    run_guard "$conf" run "$a"
    expect_status 0 "$run_status" healthy
    expect_count 1 "btrbk -c $conf run" healthy
    expect_count 0 "btrbk -c $conf prune" healthy
    expect_count 1 "lock $mount_a" healthy
    expect_count 2 "check $mount_a" healthy
    expect_before "lock $mount_a" "btrbk -c $conf run" healthy

    # A receive target that does not exist yet belongs to the filesystem where
    # it would be created, so it neither breaks the guard nor escapes the lock.
    new_case uncreated-target
    fsmap "$mount_a|btrfs|uuid-a"
    codes 0
    run_path=$bindir
    run_guard "$conf" run "$a/not-yet-created"
    expect_status 0 "$run_status" uncreated-target
    expect_count 1 "btrbk -c $conf run" uncreated-target
    expect_count 1 "lock $mount_a" uncreated-target

    # Critical pressure: retention-only prune first, then the snapshot once the
    # in-lock re-check reports healthy.
    new_case prune-then-run
    fsmap "$mount_a|btrfs|uuid-a"
    codes 75 0
    run_path=$bindir
    run_guard "$conf" run "$a"
    expect_status 0 "$run_status" prune-then-run
    expect_count 1 "btrbk -c $conf prune" prune-then-run
    expect_count 1 "btrbk -c $conf run" prune-then-run
    expect_before "btrbk -c $conf prune" "btrbk -c $conf run" prune-then-run
    # the prune phase and the snapshot phase each take the lock
    expect_count 2 "lock $mount_a" prune-then-run

    # Still critical after the prune: the snapshot is refused and the unit
    # fails, so retention stays unchanged and OnFailure reports it.
    new_case prune-refuses
    fsmap "$mount_a|btrfs|uuid-a"
    codes 75 75
    run_path=$bindir
    run_guard "$conf" run "$a"
    expect_status 75 "$run_status" prune-refuses
    expect_count 1 "btrbk -c $conf prune" prune-refuses
    expect_count 0 "btrbk -c $conf run" prune-refuses

    # A failed measurement is an error, never a healthy filesystem.
    new_case measurement-error
    fsmap "$mount_b|btrfs|uuid-b"
    codes 0
    run_path=$bindir
    run_guard "$conf" run "$a"
    expect_status 1 "$run_status" measurement-error
    expect_count 0 "btrbk " measurement-error

    # An unknown status fails closed with that status.
    new_case unknown-status
    fsmap "$mount_a|btrfs|uuid-a"
    codes 42
    run_path=$bindir
    run_guard "$conf" run "$a"
    expect_status 42 "$run_status" unknown-status
    expect_count 0 "btrbk " unknown-status

    # A filesystem already owned by maintenance stays busy: no snapshot.
    new_case lock-busy
    fsmap "$mount_a|btrfs|uuid-a"
    codes 0
    touch "$state/lock-busy"
    run_path=$bindir
    run_guard "$conf" run "$a"
    expect_status 75 "$run_status" lock-busy
    expect_count 0 "btrbk " lock-busy

    # Missing tooling must never look like a skipped-but-successful run.
    new_case missing-tool
    fsmap "$mount_a|btrfs|uuid-a"
    codes 0
    run_path=$emptybin
    run_guard "$conf" run "$a"
    expect_status 1 "$run_status" missing-tool
    expect_count 0 "btrbk " missing-tool

    # btrbk snapshots btrfs subvolumes: another filesystem is a config error.
    new_case non-btrfs
    fsmap "$mount_a|ext4|uuid-a"
    codes 0
    run_path=$bindir
    run_guard "$conf" run "$a"
    expect_status 1 "$run_status" non-btrfs
    expect_count 0 "btrbk " non-btrfs

    # No filesystem identity means no lockable guard.
    new_case no-identity
    fsmap "$mount_a|btrfs|none"
    codes 0
    run_path=$bindir
    run_guard "$conf" run "$a"
    expect_status 1 "$run_status" no-identity
    expect_count 0 "btrbk " no-identity

    # A snapshot-only instance is refused under critical pressure rather than
    # pruned or snapshotted.
    new_case snapshot-only
    fsmap "$mount_a|btrfs|uuid-a"
    codes 75
    run_path=$bindir
    run_guard "$conf" snapshot "$a"
    expect_status 75 "$run_status" snapshot-only
    expect_count 0 "btrbk " snapshot-only

    # Two distinct filesystems: both are locked before the snapshot runs.
    new_case multi-fs
    fsmap "$mount_a|btrfs|uuid-a" "$mount_b|btrfs|uuid-b"
    codes 0
    run_path=$bindir
    run_guard "$conf" run "$a" "$b"
    expect_status 0 "$run_status" multi-fs
    expect_count 1 "btrbk -c $conf run" multi-fs
    expect_count 1 "lock $mount_a" multi-fs
    expect_count 1 "lock $mount_b" multi-fs
    expect_before "lock $mount_b" "btrbk -c $conf run" multi-fs
    distinct_locks=$(grep -o 'lock [^ ]*' "$state/log" | sort -u | wc -l)
    if [ "$distinct_locks" != 2 ]; then
      fail "multi-fs: expected 2 distinct locked filesystems, got $distinct_locks (log: $(tr '\n' ';' < "$state/log"))"
    fi

    # Critical on the second filesystem: pruned under both locks, then refused
    # after the in-lock re-check, with no snapshot at all.
    new_case multi-fs-critical
    fsmap "$mount_a|btrfs|uuid-a" "$mount_b|btrfs|uuid-b"
    codes 0 75
    run_path=$bindir
    run_guard "$conf" run "$a" "$b"
    expect_status 75 "$run_status" multi-fs-critical
    expect_count 1 "btrbk -c $conf prune" multi-fs-critical
    expect_count 0 "btrbk -c $conf run" multi-fs-critical
    # both filesystems are locked in the prune phase and again in the phase
    # that refuses the snapshot
    expect_count 2 "lock $mount_a" multi-fs-critical
    expect_count 2 "lock $mount_b" multi-fs-critical
    expect_count 2 "check $mount_a" multi-fs-critical
    expect_count 1 "check $mount_b" multi-fs-critical

    # Several paths of one physical filesystem take one lock, not several.
    new_case same-fs
    mkdir -p "$a/sub"
    fsmap "$mount_a|btrfs|uuid-a"
    codes 0
    run_path=$bindir
    run_guard "$conf" run "$a" "$a/sub"
    expect_status 0 "$run_status" same-fs
    expect_count 1 "btrbk -c $conf run" same-fs
    distinct_locks=$(grep -o 'lock [^ ]*' "$state/log" | sort -u | wc -l)
    if [ "$distinct_locks" != 1 ]; then
      fail "same-fs: expected 1 distinct locked filesystem, got $distinct_locks (log: $(tr '\n' ';' < "$state/log"))"
    fi

    if [ "$failures" -ne 0 ]; then
      printf '%s guard behaviour check(s) failed\n' "$failures" >&2
      exit 1
    fi
    touch "$out"
  ''
