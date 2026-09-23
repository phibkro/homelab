{
  config,
  inputs,
  pkgs,
  ...
}:
let
  agentPackages = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  gib = 1024 * 1024 * 1024;
  herdrPaneMemoryHigh = 16 * gib;
  herdrPaneMemoryMax = 20 * gib;
  herdrPaneMemorySwapMax = 2 * gib;
in
{
  home.packages = [
    agentPackages.chatgpt # OpenAI's official Linux app, pinned by llm-agents.nix
    pkgs.chromium # wrapped Chromium for browser automation and ChatGPT Work agents
    pkgs.nvtopPackages.nvidia # GPU monitor (NVIDIA-only build, smaller closure)
    pkgs.ncdu # interactive disk usage browser
    pkgs.bandwhich # per-process / per-connection network throughput
    pkgs.compsize # btrfs actual-on-disk size + compression ratio
    pkgs.doggo # modern dig — friendlier output
    pkgs.lazysql # SQL TUI (Immich pg, Open WebUI sqlite, etc.)
    pkgs.nix-tree # interactive Nix dependency-graph viewer
    pkgs.nvd # diff between NixOS generations
    /*
      home-manager CLI for introspection (`news`, `generations`). The
      `programs.home-manager.enable` above wires only the activation
      script when HM runs as a NixOS module; the binary isn't auto-
      installed. Don't `home-manager switch` — use `just rebuild`.
    */
    pkgs.home-manager
    pkgs.pulseaudio # pactl — PipeWire/PulseAudio sink/card/port inspection (e.g. fix jack desync after replug)
  ];

  /*
    home-manager owns ~/.bashrc — lets fzf/zoxide auto-source.

    initExtra: Herdr blast-radius isolation. Every Herdr pane starts an
    interactive bash; this hook moves that shell — and thus every pane
    descendant (agents, builds) — into its own transient scope under
    herdr.slice, so systemd-oomd's smallest killable unit is one lane,
    not the whole fleet (2026-07-20: the fleet shared one ghostty scope
    and a single pressure trip killed 908 processes; see
    docs/archive/reports/2026-07-20-oomd-agent-fleet-kill.md).

    StartTransientUnit-with-PIDs (not `exec systemd-run --scope`) keeps
    the process tree and tty untouched; on failure the pane keeps
    working in the shared scope, loudly.

    Per-pane memory bounds prevent one lane from consuming the whole
    fleet budget. The 2026-09-03 incident measured one pane at 19.6 GiB
    resident plus 13.4 GiB swap and 294 processes before the parent
    user-slice pressure trigger killed it. Keep the normal working set
    resident through 16 GiB, permit an explicitly bounded climb to
    20 GiB, and cap swap at 2 GiB so a hard RAM limit cannot turn into
    unbounded zram thrash. Values are declared once above and converted
    to the uint64 byte values required by StartTransientUnit.

    ManagedOOMMemoryPressure=kill is explicit because transient scopes
    outside the app-* naming default to `auto` and would silently
    escape the oomd guardrail. The pressure LIMIT is deliberately not
    set — it inherits oomd.conf's default, one source of truth for the
    number. ManagedOOMPreference=avoid makes another viable user-owned
    cgroup the preferred victim when an owner-compatible monitored
    ancestor chooses between them. It is deliberately a preference,
    not immunity: it is not recursive, and the root-owned
    user-1000.slice emergency trigger may still select a Herdr pane.

    Success is verified by observing /proc/self/cgroup, NOT busctl's
    exit code: StartTransientUnit reports success even when the PID
    attach silently fails, which is exactly what happens when the
    shell sits outside user@'s delegated subtree (e.g. Herdr launched
    from a login-session shell — session-N.scope is root-owned, the
    user manager can't migrate out of it). The warning names the fix.
  */
  programs.bash = {
    enable = true;
    initExtra = ''
      if [[ -n ''${HERDR_PANE_ID-} && -z ''${__HERDR_PANE_SCOPE-} ]]; then
        export __HERDR_PANE_SCOPE="''${HERDR_PANE_ID}"
        if busctl call --user --quiet \
            org.freedesktop.systemd1 /org/freedesktop/systemd1 \
            org.freedesktop.systemd1.Manager StartTransientUnit \
            "ssa(sv)a(sa(sv))" \
            "herdr-''${HERDR_PANE_ID//:/-}-$$.scope" fail 8 \
            PIDs au 1 "$$" \
            Slice s herdr.slice \
            MemoryHigh t ${toString herdrPaneMemoryHigh} \
            MemoryMax t ${toString herdrPaneMemoryMax} \
            MemorySwapMax t ${toString herdrPaneMemorySwapMax} \
            ManagedOOMMemoryPressure s kill \
            ManagedOOMPreference s avoid \
            CollectMode s inactive-or-failed \
            0 2>/dev/null; then
          for _ in 1 2 3; do
            grep -q '/herdr-' /proc/self/cgroup && break
            sleep 0.1
          done
        fi
        if ! grep -q '/herdr-' /proc/self/cgroup; then
          echo "herdr-scope: pane NOT isolated — launch herdr via: systemd-run --user --scope --slice=herdr.slice herdr" >&2
        fi
      fi
    '';
  };

  /*
    Parent slice for the per-pane Herdr scopes created by the bash hook
    above. Declared (rather than left transient) so fleet-wide bounds
    have a home when needed; per-lane containment comes from each scope's
    own memory bounds and ManagedOOMMemoryPressure.

    FLEET-WIDE MEMORY CAP — 2026-07-23 incident: herdr.slice carried
    ManagedOOMMemoryPressure (a per-scope kill trigger) but no memory
    limit of its own, so the fleet's aggregate RSS grew unbounded,
    drove user-1000.slice's memory pressure past its 50% oomd trip
    (`systemd.slices."user-1000".sliceConfig.ManagedOOMMemoryPressureLimit`,
    workstation/default.nix), and oomd picked the DESKTOP session scope
    to kill — the biggest cgroup it saw, and the opposite of what the
    2026-07-20 per-pane isolation was for (that made each PANE
    killable; it never bounded the FLEET). MemoryHigh/MemoryMax give
    the slice its own hard ceiling: growth past MemoryMax now trips a
    kernel OOM INSIDE herdr.slice — killing a fleet agent — before
    user-1000's pressure trip ever has to pick a victim. ManagedOOMSwap
    extends the same "contain inside the slice" story to the swap
    axis, mirroring what MemorySwapMax does for user@ in default.nix.

    The original absolute calibration was verified live at the time of the
    incident via `systemctl --user set-property herdr.slice MemoryHigh=12G MemoryMax=16G
    ManagedOOMMemoryPressure=kill ManagedOOMSwap=kill` — that command
    does not survive a reboot, hence codifying it here.

    FIFTH CALIBRATION — 2026-08-11: repeated oomd kills were parent
    user-1000.slice pressure trips, not herdr.slice hard-cap OOMs. Live
    counters showed herdr.slice pinned at its 12G MemoryHigh with more
    than 31 million high events and zero max/oom events; 10G of its
    working set was already swapped. Raise the fleet's resident soft
    budget so hot agent pages can remain resident instead of
    continuously driving reclaim pressure. Keep the 50% parent oomd
    threshold and its victim selection unchanged: they remain the
    livelock backstop.

    Percentages preserve the containment ratios as physical RAM changes:
    Herdr's 75% hard cap remains 12.5 percentage points below the enclosing
    user slice's 87.5%, and its 62.5% soft cap remains 12.5 points below the
    parent's 75%. At 32 GiB these resolve to the measured 24/20 GiB caps; at
    64 GiB they become 48/40 GiB. Tighten if the desktop approaches its
    reserve; do not weaken the oomd pressure threshold.
  */
  systemd.user.slices.herdr = {
    Unit.Description = "Herdr agent lanes (one scope per pane)";
    Slice = {
      MemoryHigh = "62.5%";
      MemoryMax = "75%";
      ManagedOOMMemoryPressure = "kill";
      ManagedOOMSwap = "kill";
      /*
        Below-default weights (100): under contention the lanes yield
        to the interactive session instead of 4×-oversubscribing it
        (2026-07-20: two `lake build`s + `nix flake check` + 6 agents
        put a 12-core box at load 56 and CPU-PSI 75%). Lane-vs-lane
        build serialization stays a per-repo concern; this only keeps
        the DESKTOP responsive while lanes contend.
      */
      CPUWeight = 80;
      IOWeight = 80;
    };
  };

  programs.lazygit = {
    enable = true;
    settings = {
      gui.theme.lightTheme = false;
      git.paging.colorArg = "always";
    };
  };

  programs.btop = {
    enable = true;
    /*
      color_theme + theme_background managed by Stylix (src/profiles/desktop/nixos/
      stylix.nix) via the Material You palette. Set to `default` here
      would override Stylix; leave unset.
    */
  };

  programs.fzf.enable = true; # Ctrl-R history, Ctrl-T file picker, **<Tab> hooks
  programs.zoxide.enable = true; # `z <fragment>` jumps to most-used dir match

  /*
    ~/nori + the standard working folders are out-of-store symlinks into the
    @srv-nori subvolume (networked over Samba + own backup tier). Canonical
    data lives on /srv/nori; apps use the normal home paths; Samba serves the
    real dirs natively (no follow-symlink needed). This is the allowlist shape:
    only these harmless working dirs are relocated onto the share — secrets
    (~/.ssh, ~/.config/sops, ~/.claude.json) stay on @home and never enter the
    shared tree, so there's nothing to filter out. /srv/nori only exists on
    workstation, so this lives here, not in the cross-machine core.nix.
  */
  home.file =
    let
      link = target: {
        source = config.lib.file.mkOutOfStoreSymlink target;
      };
    in
    {
      "nori" = link "/srv/nori";
      "Documents" = link "/srv/nori/Documents";
      "Videos" = link "/srv/nori/Videos";
      "Photos" = link "/srv/nori/Photos";
      "Downloads" = link "/srv/nori/Downloads";
      "Desktop" = link "/srv/nori/Desktop";
      "Projects" = link "/srv/nori/Projects";

    };

}
