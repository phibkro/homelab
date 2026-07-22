/**
  e2e-hypr-session — REAL user-journey nixosTest for hypr-session.

  Boots a minimal NixOS guest with a real Hyprland compositor (virtio-gpu
  + llvmpipe software rendering — no host DRM access by construction; a
  2026-07-20 attempt to run "headless" Hyprland on a dev host had
  aquamarine seize the real GPU and killed the operator's session, so
  compositor isolation is now structural, not prose) and drives the whole
  design-doc journey (docs/specs/2026-07-20-hypr-session-persistence-
  design.md § Definition of Done):

    1. logd subscribes to socket2 and converges current.json to reality
       (window count, workspaces, /proc cwds, floating geometry, shown
       special, focus) within one debounce window.
    2. kill -9 logd mid-churn → current.json stays a valid v1 snapshot
       (the RPO/durability claim: atomic tmp+rename, ring append).
    3. save / list --json round-trip a named session.
    4. Compositor killed uncleanly (SIGKILL — the crash case, not a clean
       exit); a FRESH instance (new HYPRLAND_INSTANCE_SIGNATURE) comes up;
       restore replays the saved session against it.
    5. Every restorable window respawns with the right class, workspace /
       special, and working directory; shown special + focus land; the
       report JSON is loud about anything unrestorable.

  Real values, not stubs (docs/reference/testing-methodology.md): the
  compositor, socket2 stream, foot clients, /proc reads, and every
  hyprctl dispatch are the real thing. The only synthetic artifact is the
  dead-pid session used to prove the unrestorable-report path, built by
  jq from a REAL saved snapshot and replayed via --diff (dispatch-free).

  Layer 2 (nixosTest). Run: `just test-hypr-session-e2e`, or iterate via
  `just e2e-shell e2e-hypr-session` (driverInteractive, boot once).
  Invoked via nix build .#checks.<system>.e2e-hypr-session.
*/
{ pkgs, ... }:

let
  hyprSession = pkgs.callPackage ../. { };

  /*
    Journey helpers baked into the guest instead of inlined in testScript:
    every hyprctl dispatch carries lua-builder quoting (gotcha-hyprland-
    lua-migration) that would otherwise be triple-escaped through
    python → su → bash. Each runs as the session user with
    HYPRLAND_INSTANCE_SIGNATURE / XDG_RUNTIME_DIR / HYPR_SESSION_STATE_DIR
    injected by the testScript's user_cmd().
  */

  # Three real foot windows, distinct cwds: tiled on ws 1, floating
  # (via the e2e-float window rule matching app-id) on ws 1, and one
  # spawned straight into a named special workspace with the
  # live-verified "special:NAME silent" exec_cmd idiom.
  #
  # The cwd carrier is the -D flag in argv: foot's main process chdirs
  # itself to / (observed in-VM — windows[].process.cwd is "/" no matter
  # where it was spawned from), so cmdline is the only place the working
  # directory survives capture for foot, and the DEFAULT adapter's
  # verbatim-cmdline replay is what reproduces the shell's cwd after
  # restore (asserted via the respawned foot's child shell in
  # e2e-check-restore).
  e2eSeed = pkgs.writeShellScriptBin "e2e-seed" ''
    set -euo pipefail
    mkdir -p /tmp/e2e/alpha /tmp/e2e/beta /tmp/e2e/gamma
    hyprctl dispatch 'hl.dsp.exec_cmd("cd /tmp/e2e/alpha && exec foot -D /tmp/e2e/alpha")'
    hyprctl dispatch 'hl.dsp.exec_cmd("cd /tmp/e2e/beta && exec foot --app-id=foot-float -D /tmp/e2e/beta")'
    hyprctl dispatch 'hl.dsp.exec_cmd("cd /tmp/e2e/gamma && exec foot -D /tmp/e2e/gamma", { workspace = "special:files silent" })'
  '';

  # Nudge the floating window off the rule's default placement, then echo
  # the resulting {at, size}. The testScript compares against the target
  # (100,80 / 500x300): if the move/resize dispatch grammar works, the
  # later restore-side geometry assertion is meaningful; if it doesn't,
  # this surfaces it as evidence instead of a false green (restore.sh
  # flags exactly this dispatch as UNVERIFIED in its header).
  e2eFloatGeometry = pkgs.writeShellScriptBin "e2e-float-geometry" ''
    set -euo pipefail
    addr=$(hyprctl clients -j | jq -r '.[] | select(.class == "foot-float") | .address')
    hyprctl dispatch "hl.dsp.window.move({ window = \"address:$addr\", x = 100, y = 80, exact = true })" >/dev/null
    hyprctl dispatch "hl.dsp.window.resize({ window = \"address:$addr\", width = 500, height = 300, exact = true })" >/dev/null
    sleep 1
    hyprctl clients -j | jq -c --arg a "$addr" '.[] | select(.address == $a) | {at, size}'
  '';

  # Show special:files (positional-string toggle_special — the table form
  # is confirmed broken) and focus the window on it, so capture records
  # focus-as-state: a shown special + a focused window.
  e2eShowSpecial = pkgs.writeShellScriptBin "e2e-show-special" ''
    set -euo pipefail
    gaddr=$(hyprctl clients -j | jq -r '.[] | select(.workspace.name == "special:files") | .address')
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("files")' >/dev/null
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$gaddr\" })" >/dev/null
  '';

  e2eToggleSpecial = pkgs.writeShellScriptBin "e2e-toggle-special" ''
    set -euo pipefail
    hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$1\")" >/dev/null
  '';

  # Full-fidelity assertion over current.json — the capture side of the
  # journey. jq -e: nonzero exit on any clause failing, so this slots
  # straight into wait_until_succeeds.
  e2eCheckCapture = pkgs.writeShellScriptBin "e2e-check-capture" ''
    set -euo pipefail
    f="$HYPR_SESSION_STATE_DIR/current.json"
    test -f "$f"
    jq -e '
      .version == 1
      and (.windows | length == 3)
      and ([.windows[] | select(
            .class == "foot" and .workspace == "1"
            and .process.cwd != null
            and .process.cmdline == ["foot", "-D", "/tmp/e2e/alpha"])] | length == 1)
      and ([.windows[] | select(
            .class == "foot-float" and .workspace == "1" and .floating
            and .geometry != null
            and .process.cmdline
                == ["foot", "--app-id=foot-float", "-D", "/tmp/e2e/beta"])] | length == 1)
      and ([.windows[] | select(
            .class == "foot" and .workspace == "special:files"
            and .process.cmdline == ["foot", "-D", "/tmp/e2e/gamma"])] | length == 1)
      and (.focus.monitors[0].special_workspace == "special:files")
      and (.focus.focused_window != null)
      and (.focus.focused_window
           == ([.windows[] | select(.workspace == "special:files")][0].address))
    ' "$f" >/dev/null
  '';

  # Post-restore assertion against the FRESH instance's hyprctl: classes,
  # workspace/special placement, working directories (via the respawned
  # foot's child shell — the -D argv replay is what carries cwd through
  # the default adapter), shown special, and focus.
  e2eCheckRestore = pkgs.writeShellScriptBin "e2e-check-restore" ''
    set -euo pipefail
    clients=$(hyprctl clients -j)
    test "$(jq 'length' <<<"$clients")" = 3

    shell_cwd() {
      local child
      child=$(pgrep -P "$1" | head -n1)
      readlink -f "/proc/$child/cwd"
    }

    apid=$(jq -r '.[] | select(.class == "foot" and .workspace.name == "1") | .pid' <<<"$clients")
    test "$(shell_cwd "$apid")" = /tmp/e2e/alpha

    bjson=$(jq -c '.[] | select(.class == "foot-float")' <<<"$clients")
    test -n "$bjson"
    test "$(jq -r '.floating' <<<"$bjson")" = true
    test "$(jq -r '.workspace.name' <<<"$bjson")" = 1
    test "$(shell_cwd "$(jq -r '.pid' <<<"$bjson")")" = /tmp/e2e/beta

    gjson=$(jq -c '.[] | select(.class == "foot" and .workspace.name == "special:files")' <<<"$clients")
    test -n "$gjson"
    test "$(shell_cwd "$(jq -r '.pid' <<<"$gjson")")" = /tmp/e2e/gamma

    test "$(hyprctl monitors -j | jq -r '.[0].specialWorkspace.name')" = special:files
    test "$(hyprctl activewindow -j | jq -r '.address')" = "$(jq -r '.address' <<<"$gjson")"
  '';

  e2eGetFloatGeometry = pkgs.writeShellScriptBin "e2e-get-float-geometry" ''
    set -euo pipefail
    hyprctl clients -j | jq -c '.[] | select(.class == "foot-float") | {at, size, floating}'
  '';

  # Derive a dead-pid session from a REAL saved one: one extra window
  # whose process is null (pid was dead at capture time). named/<name>.json
  # is a raw v1 snapshot (cli.sh embeds label/created_at as extra top-level
  # fields rather than wrapping — the 2026-07-20 save↔restore seam fix), so
  # the windows array is at the top level. Replayed with --diff so the
  # unrestorable-report path is exercised dispatch-free.
  e2eMakeDeadSession = pkgs.writeShellScriptBin "e2e-make-dead-session" ''
    set -euo pipefail
    src="$HYPR_SESSION_STATE_DIR/named/$1.json"
    dst="$HYPR_SESSION_STATE_DIR/named/$2.json"
    jq '.windows += [{
      address: "0xdead", class: "ghost", title: "gone", workspace: "1",
      floating: false, geometry: null, process: null, identity: null
    }]' "$src" >"$dst"
  '';
in
pkgs.testers.runNixOSTest {
  name = "e2e-hypr-session";

  nodes.machine =
    { pkgs, ... }:
    {
      users.users.nori = {
        isNormalUser = true;
        uid = 1000;
        extraGroups = [
          "video"
          "input"
        ];
      };

      # tty1 autologin gives a real logind seat session — aquamarine gets
      # DRM/input through libseat's logind backend exactly like a
      # physical login (same pattern as nixpkgs' sway test).
      services.getty.autologinUser = "nori";

      hardware.graphics.enable = true;
      fonts.packages = [ pkgs.dejavu_fonts ]; # foot needs a resolvable monospace

      environment.systemPackages = [
        pkgs.hyprland
        pkgs.foot
        pkgs.jq
        hyprSession
        e2eSeed
        e2eFloatGeometry
        e2eShowSpecial
        e2eToggleSpecial
        e2eCheckCapture
        e2eCheckRestore
        e2eGetFloatGeometry
        e2eMakeDeadSession
      ];

      /*
        Lua-mode config (this homelab is post-hyprlang; restore.sh's
        dispatches are lua-builder-form and MUST run against a lua-mode
        compositor). Reached via XDG_CONFIG_HOME=/etc/hypr-e2e at launch.
        The float rule exists because restore never floats a window
        itself (floating-ness is app/rule-driven; restore only reapplies
        geometry to windows that come back floating) — same shape as the
        rice's pwvucontrol/ghostty float rules.
      */
      environment.etc."hypr-e2e/hypr/hyprland.lua".text = ''
        hl.config({
            cursor = { no_hardware_cursors = true },
        })
        hl.window_rule({
            name  = "e2e-float",
            match = { class = "^foot-float$" },
            float = true,
        })
      '';

      # virtio-gpu KMS + llvmpipe: a real DRM device for aquamarine with
      # zero host GPU exposure (the QEMU boundary is the isolation).
      virtualisation.qemu.options = [
        "-vga none"
        "-device virtio-gpu-pci"
      ];
      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;
    };

  testScript = ''
    import json
    import shlex

    STATE = "/tmp/hypr-session-state"
    RUNTIME = "/run/user/1000"


    def user_cmd(cmd, sig):
        """Run cmd as the session user with the hypr-session env contract:
        HYPRLAND_INSTANCE_SIGNATURE + XDG_RUNTIME_DIR untouched passthrough,
        HYPR_SESSION_STATE_DIR at a temp dir, short debounce for test speed,
        generous restore polling for llvmpipe-slow foot startups."""
        env = (
            f"HYPRLAND_INSTANCE_SIGNATURE={sig} "
            f"XDG_RUNTIME_DIR={RUNTIME} "
            f"HYPR_SESSION_STATE_DIR={STATE} "
            "HYPR_SESSION_DEBOUNCE_SECONDS=1 "
            "HYPR_SESSION_RESTORE_MAX_POLLS=80 "
            "HYPR_SESSION_RESTORE_POLL_INTERVAL=0.5 "
        )
        return "su - nori -c " + shlex.quote(env + cmd)


    def as_user(cmd, sig):
        return machine.succeed(user_cmd(cmd, sig))


    def as_user_json(cmd, sig):
        # Last stdout line: login-shell noise (if any) must not break parsing.
        return json.loads(as_user(cmd, sig).strip().splitlines()[-1])


    def launch_hyprland(logfile):
        machine.send_chars(
            "env XDG_CONFIG_HOME=/etc/hypr-e2e "
            "LIBGL_ALWAYS_SOFTWARE=1 WLR_NO_HARDWARE_CURSORS=1 "
            f"Hyprland > {logfile} 2>&1\n"
        )


    def start_logd(sig, logfile):
        machine.succeed(
            user_cmd(f"setsid hypr-session-logd > {logfile} 2>&1 < /dev/null &", sig)
        )
        # [d] bracket: keeps the pattern from matching the pgrep-invoking
        # shell's own cmdline (which contains the literal pattern text).
        machine.wait_until_succeeds("pgrep -f 'hypr-session-log[d]'")


    def dump_state(sig):
        """Failure forensics: what did capture write vs what is live."""
        for probe in (
            f"cat {STATE}/current.json",
            "cat /tmp/logd-*.log",
            "tail -c 2000 /tmp/hypr-*.log",
        ):
            print(f"--- {probe}\n" + machine.execute(probe)[1])
        for probe in (
            "hyprctl clients -j",
            "hyprctl monitors -j",
            "hyprctl activewindow -j",
        ):
            print(f"--- {probe}\n" + machine.execute(user_cmd(probe, sig))[1])


    def wait_or_dump(cmd, sig, timeout):
        try:
            machine.wait_until_succeeds(user_cmd(cmd, sig), timeout=timeout)
        except Exception:
            dump_state(sig)
            raise


    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_until_tty_matches("1", "nori\\@machine")

    with subtest("hyprland instance 1 boots on virtio-gpu/llvmpipe"):
        launch_hyprland("/tmp/hypr-1.log")
        machine.wait_until_succeeds(f"ls {RUNTIME}/hypr/*/.socket2.sock", timeout=180)
        sig1 = machine.succeed(f"ls {RUNTIME}/hypr").strip()
        machine.wait_until_succeeds(
            user_cmd("hyprctl monitors -j | jq -e 'length >= 1'", sig1), timeout=120
        )

    with subtest("logd subscribes to instance 1's socket2"):
        start_logd(sig1, "/tmp/logd-1.log")

    with subtest("real foot windows across normal + special workspaces"):
        as_user("e2e-seed", sig1)
        machine.wait_until_succeeds(
            user_cmd("hyprctl clients -j | jq -e 'length == 3'", sig1), timeout=180
        )
        geom = json.loads(as_user("e2e-float-geometry", sig1).strip().splitlines()[-1])
        # Tracked separately: restore.sh flags this whole dispatch family
        # UNVERIFIED; the seed observation decides which half of the
        # restore-side geometry equality is meaningful evidence.
        move_seeded = geom["at"] == [100, 80]
        resize_seeded = geom["size"] == [500, 300]
        if not (move_seeded and resize_seeded):
            print(f"WARNING: geometry dispatch partial: move={move_seeded} "
                  f"resize={resize_seeded}, got {geom}")
        as_user("e2e-show-special", sig1)

    with subtest("current.json converges to reality after debounce"):
        wait_or_dump("e2e-check-capture", sig1, 90)

    with subtest("kill -9 logd mid-churn: current.json stays a valid v1 snapshot"):
        # Same shell so the SIGKILL lands inside the 1s debounce window
        # opened by the toggle's topology event.
        machine.succeed(
            user_cmd("e2e-toggle-special files", sig1)
            + " && pkill -9 -f 'hypr-session-log[d]'"
        )
        machine.succeed(f"jq -e '.version == 1' {STATE}/current.json")
        machine.succeed(f"jq -s -e 'length >= 1' {STATE}/log.jsonl")
        start_logd(sig1, "/tmp/logd-2.log")
        # Restore the pre-kill topology (special shown + gamma focused);
        # the toggle emits the topology event that triggers recapture.
        as_user("e2e-show-special", sig1)
        wait_or_dump("e2e-check-capture", sig1, 90)

    with subtest("save + list --json round-trip"):
        as_user("hypr-session save e2e-test", sig1)
        listing = as_user_json("hypr-session list --json", sig1)
        assert any(s["name"] == "e2e-test" for s in listing["named"]), listing
        assert listing["last"] is not None, listing

    with subtest("compositor dies uncleanly; fresh instance comes up"):
        machine.succeed("pkill -9 -f '[H]yprland'")
        machine.succeed("pkill -9 -x foot || true")
        machine.wait_until_succeeds("! pgrep -f '[H]yprland' && ! pgrep -x foot")
        # logd must notice socket2 EOF and exit on its own — no SIGTERM sent.
        machine.wait_until_succeeds("! pgrep -f 'hypr-session-log[d]'", timeout=30)
        launch_hyprland("/tmp/hypr-2.log")
        machine.wait_until_succeeds(
            f"ls {RUNTIME}/hypr | grep -vx {sig1}", timeout=180
        )
        sig2 = machine.succeed(f"ls {RUNTIME}/hypr | grep -vx {sig1}").strip()
        machine.wait_until_succeeds(
            user_cmd("hyprctl monitors -j | jq -e 'length >= 1'", sig2), timeout=120
        )
        machine.succeed(user_cmd("hyprctl clients -j | jq -e 'length == 0'", sig2))
        start_logd(sig2, "/tmp/logd-3.log")

    with subtest("cli-saved session restores DIRECTLY into the fresh instance"):
        # Round-1 red: save wrote {label, created_at, snapshot} while
        # restore read a raw v1 snapshot ("unsupported snapshot schema
        # version: null"). Fixed by embedding label/created_at into the
        # snapshot itself — so the cli-saved file MUST now restore with
        # no unwrap step.
        report = as_user_json("hypr-session restore e2e-test --json", sig2)
        assert report["unrestorable"] == [], report
        spawns = [r for r in report["restored"] if r["action"] == "spawn"]
        assert len(spawns) == 3, report

    with subtest("restored topology matches the snapshot (class/ws/cwd/special/focus)"):
        wait_or_dump("e2e-check-restore", sig2, 120)

    with subtest("floating geometry reapplied on the restored window"):
        g = json.loads(as_user("e2e-get-float-geometry", sig2).strip().splitlines()[-1])
        assert g["floating"] is True, g
        if move_seeded:
            assert g["at"] == [100, 80], (
                f"floating position NOT reapplied (restore.sh's flagged-UNVERIFIED "
                f"dispatch is broken for real): {g}"
            )
        else:
            print(f"move dispatch never verified at seed time; restored: {g}")
        if resize_seeded:
            assert g["size"] == [500, 300], f"floating size NOT reapplied: {g}"
        else:
            print(f"resize dispatch never verified at seed time; restored: {g}")

    with subtest("restore report is loud about unrestorable windows"):
        as_user("e2e-make-dead-session e2e-test e2e-dead", sig2)
        dead = as_user_json("hypr-session restore e2e-dead --diff --json", sig2)
        assert dead["diff"] is True, dead
        ghosts = [u for u in dead["unrestorable"] if u["address"] == "0xdead"]
        assert len(ghosts) == 1, dead
        assert "no process data" in ghosts[0]["reason"], dead
        # Round-1 red: --diff skipped the reconciliation poll but still
        # routed floating/focused records through the apply loop,
        # fabricating "could not be re-matched" unrestorable entries for
        # dispatches it deliberately never made. Fixed: --diff reports
        # intent only — the ghost must be the ONLY unrestorable entry.
        extra = [u for u in dead["unrestorable"] if u["address"] != "0xdead"]
        assert extra == [], (
            f"--diff fabricates unrestorable entries for records it never "
            f"attempted to resolve: {extra}"
        )

    with subtest("--diff on the named session is dispatch-free intent, not action"):
        # Same fresh instance: a --diff replay right after the real
        # restore must not spawn a 4th window (dispatch-free) and must
        # still report full spawn intent.
        diff = as_user_json("hypr-session restore e2e-test --diff --json", sig2)
        assert diff["diff"] is True, diff
        assert len([r for r in diff["restored"] if r["action"] == "spawn"]) == 3, diff
        assert diff["unrestorable"] == [], diff
        machine.succeed(user_cmd("hyprctl clients -j | jq -e 'length == 3'", sig2))
  '';
}
