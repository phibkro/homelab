/*
  Pressure-safe snapshot policy — see
  docs/specs/2026-10-07-storage-pressure.md § "Snapshot policy".

  The generated guard runs against disposable pressure and backup adapters.
  The cases cover refusal, retention cleanup, lock ownership, and source/target
  filesystem identity. Assertions observe operations and exit status rather
  than option copies or log wording. Unit deployment is checked through the
  real workstation service after activation.
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
