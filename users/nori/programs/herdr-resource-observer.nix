{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.nori.herdrResourceObserver;
  herdrPkg = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.nori.herdrResourceObserver.enable = lib.mkEnableOption "observe Herdr agent cgroup memory use without changing limits";

  config = lib.mkIf cfg.enable {
    systemd.user.services.herdr-resource-observer = {
      Unit.Description = "Record Herdr agent cgroup resource observations";
      Service = {
        Type = "oneshot";
        StateDirectory = "herdr-resource-observer";
        Environment = "PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.findutils
            pkgs.gawk
            pkgs.jq
            herdrPkg
          ]
        }";
        ExecStart = pkgs.writeShellScript "herdr-resource-observer" ''
          set -eu
          state_dir="''${STATE_DIRECTORY:-$HOME/.local/state/herdr-resource-observer}"
          mkdir -p "$state_dir"
          agents="$(herdr agent list 2>/dev/null | jq -r '.result.agents[]? | [(.name // .pane_id), .pane_id] | @tsv' || true)"
          report="$state_dir/latest.json"
          {
            printf '{"observedAt":"%s","mode":"observe-only","agents":[' "$(date --iso-8601=seconds)"
            first=1
            while IFS=$'\t' read -r name pane; do
              [ -n "''${pane:-}" ] || continue
              safe="''${pane//:/-}"
              scope="$(basename "$(find /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/herdr.slice -maxdepth 1 -type d -name "herdr-$safe-*.scope" -print -quit 2>/dev/null || true)")"
              [ -n "$scope" ] || continue
              dir="/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/herdr.slice/$scope"
              current="$(cat "$dir/memory.current")"; peak="$(cat "$dir/memory.peak")"
              psi="$(awk '$1=="full" {for(i=2;i<=NF;i++) if($i ~ /^avg10=/){split($i,a,"=");print a[2]}}' "$dir/memory.pressure")"
              [ "$first" = 1 ] || printf ','; first=0
              jq -n --arg name "$name" --arg pane "$pane" --arg scope "$scope" --argjson current "$current" --argjson peak "$peak" --arg psi "''${psi:-0}" '{name:$name,paneId:$pane,scope:$scope,memoryCurrentBytes:$current,memoryPeakBytes:$peak,memoryFullAvg10Pct:($psi|tonumber),priority:"unclassified"}'
            done <<EOF
          $agents
          EOF
            printf ']}\n'
          } > "$report"
        '';
      };
    };
    systemd.user.timers.herdr-resource-observer = {
      Unit.Description = "Periodic Herdr resource observation";
      Timer = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1min";
        AccuracySec = "15s";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
