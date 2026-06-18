#!/usr/bin/env just --justfile
# Common workflows for the nori homelab flake.
#
# Recipes default to running LOCALLY — on whichever host you invoke
# them from. Cross-host execution composes via the `remote` recipe:
#
#   just rebuild                            # build the host you're sitting on
#   just remote workstation rebuild         # rsync working tree to workstation
#                                            # + run `just rebuild` there
#   just remote workstation show-status     # ssh + run `just show-status` there
#   just remote workstation show-logs sshd  # forwarded args work
#
# Implications:
#   - On macOS / Mac dev box: most recipes don't make sense locally
#     (Mac isn't a NixOS host). Use `just remote <host> <recipe>`.
#   - Inside Zed-remote SSH'd into a NixOS host: plain `just rebuild`
#     builds that host — no rsync-back-to-self absurdity.
#
# Install: `brew install just` on macOS; `pkgs.just` (already in
# common/base.nix systemPackages) on NixOS hosts.
#
# ── Recipe-authoring conventions ──────────────────────────────────
#
# 1. **Naming: verb-object.** A recipe name carries both a VERB and
#    an OBJECT (`list-ports`, `show-logs`, `generate-oidc-key`,
#    `test-hypr`). Single-verb names (`rebuild`, `preview`, `boot`,
#    `deploy`) are OK only when the object is "this host's current
#    config" — implicit + universal. Pure nouns (`pending`, `status`,
#    `ports`) are wrong: no verb means unclear what the recipe does.
#
# 2. **The LAST `#` comment line above a recipe is its `just --list`
#    description.** `just --list` shows only that line; multi-line
#    doc-blocks lose all but the last. Write the last line as a
#    self-contained one-liner. Multi-line elaboration goes ABOVE that
#    one-liner, not below.
#
# 3. **Cluster naming.** Test recipes are `test-<thing>`; build flow
#    is `build/preview/rebuild/boot/rollback`; observation is `show-X`,
#    `list-X`, `query-X`; generation is `generate-X`. Match the cluster
#    when adding a new recipe so `just --list | grep ^<verb>-` finds it.

default_host := "workstation"
user         := "nori"
remote_path  := "/tmp/nix-migration"
tailnet      := "saola-matrix.ts.net"

# Every NixOS host in the homelab. Macbook is intentionally NOT here —
# it's a standalone home-manager target, not part of the NixOS flake.
# Used by `rebuild-homelab` to fan rebuild across the set.
homelab_hosts := "workstation pi aurora pavilion"

# rsync flags — BSD openrsync compatible (Mac default rsync is openrsync;
# some GNU flags like --info=stats2 fail silently). See docs/gotchas.md.
rsync_args := "-aH --no-owner --no-group --partial --delete --exclude='.git' --exclude='result' --exclude='inventory-*'"

# Default recipe — rebuild this host.
default: rebuild

# Show all recipes with their docs.
@list:
    just --list --justfile {{justfile()}}

# === remote — composition primitive ===

# Run a recipe on another host via tailnet SSH.
# Rsyncs the local working tree to {{remote_path}} on <host>, then runs
# `just <recipe>` there. Args after <recipe> forward to the recipe.
# Usage: just remote <host> <recipe> [<args>...]
@remote host +recipe:
    rsync {{rsync_args}} ./ {{user}}@{{host}}.{{tailnet}}:{{remote_path}}/
    ssh -t {{user}}@{{host}}.{{tailnet}} 'cd {{remote_path}} && just {{recipe}}'

# === build / deploy (local) ===

# Build + activate this host's configuration from the working tree.
@rebuild *args:
    nh os switch . -H $(hostname) {{args}}

# Sequential rebuild: local first (catches typos fast), then each remote.
# Use after any change that affects multiple hosts — most commonly adding
# a new `nori.lanRoutes.<n>` entry. `just rebuild` only touches whichever
# host you're sitting on; this fans across the homelab set
# ({{homelab_hosts}}) to avoid silent split-brain.
# Build + activate workstation + pi from the working tree.
@rebuild-homelab *args:
    for h in {{homelab_hosts}}; do \
      if [ "$h" = "$(hostname)" ]; then \
        echo "=== local ($h) ==="; \
        just rebuild {{args}}; \
      else \
        echo "=== remote $h ==="; \
        just remote $h rebuild {{args}}; \
      fi; \
    done

# Build but don't activate.
@build *args:
    nh os build . -H $(hostname) {{args}}

# Ideal for iterating on visual / UX changes (icon themes, Hyprland
# binds, fonts) without polluting the boot menu with throwaway
# generations. Once happy: `just rebuild` to persist as the new default.
#
# Activate the rebuild for the current session only — reverts on reboot.
@preview *args:
    nh os test . -H $(hostname) {{args}}

# Catches the silent class where "metrics exist somewhere but not
# from where we expect." Every host we expect data from is scraped
# (`up=1`), process-exporter is publishing series, pi heartbeat is
# firing, gatus has zero failing probes.
#
# Runtime-introspection test: VM scrape coverage + exporter series + pi heartbeat + gatus probes.
@test-observability:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    VM=http://100.100.71.3:8428

    echo "=== Tier 1 — VictoriaMetrics scrape targets all up ==="
    targets=$(curl -s "$VM/api/v1/targets?state=any" \
              | nix shell nixpkgs#jq -c jq -r '.data.activeTargets[] | "\(.health)\t\(.labels.job)\t\(.labels.host // .labels.instance)"')
    bad=$(echo "$targets" | awk -F'\t' '$1 != "up"')
    if [[ -z "$bad" ]]; then
      n=$(echo "$targets" | wc -l)
      echo "  ✓ all $n scrape targets up"
    else
      echo "  ✗ unhealthy targets:"
      echo "$bad" | awk -F'\t' '{ printf "      %s/%s [%s]\n", $2, $3, $1 }'
      fail=1
    fi

    echo "=== Tier 2 — process-exporter publishing per host ==="
    for host in workstation pavilion aurora; do
      count=$(curl -sG "$VM/api/v1/query" \
              --data-urlencode "query=count(namedprocess_namegroup_memory_bytes{host=\"$host\",memtype=\"resident\"})" \
              | nix shell nixpkgs#jq -c jq -r '.data.result[0].value[1] // "0"')
      if [[ "$count" -ge 10 ]]; then
        echo "  ✓ $host: $count process series"
      else
        echo "  ✗ $host: only $count series (expected ≥10)"; fail=1
      fi
    done

    echo "=== Tier 3 — pi heartbeat fired recently (<90s) ==="
    # heartbeat timer is 60s; allow 90s buffer for jitter.
    # ExecMainExitTimestamp on Type=oneshot lags behind actual runs
    # (caught 2026-06-07); StateChangeTimestamp tracks the latest
    # active→inactive transition, which IS each successful run.
    last=$(ssh -o ConnectTimeout=3 nori@100.100.71.3 \
             'systemctl show heartbeat.service -p StateChangeTimestampMonotonic --value' 2>/dev/null)
    uptime_us=$(ssh -o ConnectTimeout=3 nori@100.100.71.3 \
                  'cat /proc/uptime | awk "{ printf \"%d\", \$1 * 1000000 }"' 2>/dev/null)
    if [[ -n "$last" && -n "$uptime_us" && "$last" != "0" ]]; then
      age_s=$(( (uptime_us - last) / 1000000 ))
      if [[ "$age_s" -le 90 ]]; then
        echo "  ✓ heartbeat last fired ${age_s}s ago"
      else
        echo "  ✗ heartbeat last fired ${age_s}s ago (>90s)"; fail=1
      fi
    else
      echo "  · heartbeat state unreadable (last=$last uptime=$uptime_us)"
    fi

    echo "=== Tier 4 — Gatus reports zero failing probes ==="
    failing=$(curl -sG "$VM/api/v1/query" \
              --data-urlencode 'query=sum(gatus_results_endpoint_success == 0)' \
              | nix shell nixpkgs#jq -c jq -r '.data.result[0].value[1] // "0"')
    if [[ "$failing" -eq 0 ]]; then
      echo "  ✓ no failing gatus probes"
    else
      echo "  ✗ $failing gatus probes currently failing"; fail=1
    fi

    echo
    [[ "$fail" -eq 0 ]] && echo "=== ALL PASS ===" || { echo "=== FAIL ==="; exit 1; }

# Use after a multi-effect deploy (anything touching modules/effects/
# or home/) to verify declared intent landed at every runtime layer.
#
# Composite runtime-introspection: runs all `test-*` recipes. ~3 min wall, one signal.
@test:
    just test-hypr
    just test-backups
    just test-routes
    just test-observability
    just test-replicas
    just test-authelia

# Each `nori.lanRoutes.<X>` is a Reader-Writer effect: one declaration
# emits Caddy route + Gatus monitor + DNS record + (optional) Authelia
# OIDC client. The test walks each layer for desync from the declaration.
#
# Post-ADR-0003 the Caddy + Blocky entry plane lives on pi — DNS for
# `*.${nori.domain}` resolves to pi's LAN IP regardless of which host
# runs the backend (`runsOn`). The Caddy admin probe SSHes to pi; the
# DNS + HTTPS probes run from wherever you invoke `just test-routes`.
#
# Runtime-introspection test: `nori.lanRoutes.<X>` → Caddy + Gatus + DNS + OIDC, per layer.
@test-routes:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0

    host_self=$(hostname)
    flake_ref=".#nixosConfigurations.${host_self}.config"
    declared=$(nix eval --json "${flake_ref}.nori.lanRoutes" \
                 --apply 'r: builtins.attrNames r' 2>/dev/null \
               | nix shell nixpkgs#jq -c jq -r '.[]')
    domain=$(nix eval --raw "${flake_ref}.nori.domain" 2>/dev/null)
    # nori.lanIp is overridden to pi's lanIp in modules/common — every
    # declared route's customDNS entry resolves here regardless of
    # `runsOn`, because pi runs the entry-plane Caddy.
    expected_ip=$(nix eval --raw "${flake_ref}.nori.lanIp" 2>/dev/null)
    pi_tailnet=$(nix eval --raw "${flake_ref}.nori.hosts.pi.tailnetIp" 2>/dev/null)

    # Caddy admin is 127.0.0.1:2019 on pi. Whether we're on pi or any
    # other host, route the call through pi locally so the admin
    # endpoint stays loopback-only.
    if [[ "$host_self" == "pi" ]]; then
      caddy_json=$(curl -s http://127.0.0.1:2019/config/apps/http/servers/srv0/routes/ 2>/dev/null || true)
    else
      caddy_json=$(ssh -o ConnectTimeout=3 "nori@${pi_tailnet}" \
                     'curl -s http://127.0.0.1:2019/config/apps/http/servers/srv0/routes/' 2>/dev/null || true)
    fi
    caddy_hosts=$(echo "$caddy_json" \
                  | nix shell nixpkgs#jq -c jq -r '.[] | .match[]?.host[]?' 2>/dev/null \
                  | sort -u || true)

    echo "=== Tier 1 — Caddy registry contains every declared route (via pi) ==="
    for route in $declared; do
      vhost="${route}.${domain}"
      if echo "$caddy_hosts" | grep -qx "$vhost"; then
        echo "  ✓ $vhost"
      else
        echo "  ✗ $vhost NOT in Caddy registry"; fail=1
      fi
    done

    echo "=== Tier 2 — DNS resolves each declared route (via blocky on pi) ==="
    for route in $declared; do
      vhost="${route}.${domain}"
      ip=$(nix shell nixpkgs#dig -c dig +short +time=2 +tries=1 "$vhost" @${pi_tailnet} 2>/dev/null | head -1)
      if [[ "$ip" == "$expected_ip" ]]; then
        echo "  ✓ $vhost → $ip"
      else
        echo "  ✗ $vhost resolved to '$ip' (expected '$expected_ip')"; fail=1
      fi
    done

    echo "=== Tier 3 — HTTPS responsive (TLS + service alive) ==="
    for route in $declared; do
      vhost="${route}.${domain}"
      # Accept any non-5xx — auth gates may 401/302 which is healthy.
      status=$(curl -s -m 4 -o /dev/null -w '%{http_code}' "https://$vhost/" 2>/dev/null || echo "000")
      if [[ "$status" =~ ^[234][0-9][0-9]$ ]]; then
        echo "  ✓ $vhost (HTTP $status)"
      else
        echo "  ✗ $vhost unreachable (status=$status)"; fail=1
      fi
    done

    echo
    [[ "$fail" -eq 0 ]] && echo "=== ALL PASS ===" || { echo "=== FAIL ==="; exit 1; }

# Authelia is the value-prop linchpin for family-tier services: every
# OIDC route depends on it. When it silently goes wrong (sops key
# rotation without `sops updatekeys`, config schema drift on upgrade,
# OIDC client count desync), users discover via "login is broken" and
# the operator hears about it from a phone. Catch it on a probe instead.
#
# Tier 1 — systemd: authelia-main.service is active on pi.
# Tier 2 — health: /api/health responds OK via the local loopback.
# Tier 3 — OIDC: /.well-known/openid-configuration declares the right
#                issuer (caddy reverse-proxy + cert + authelia all
#                compose cleanly).
# Tier 4 — clients: count of OIDC clients authelia knows about ==
#                   count of nori.lanRoutes.<X>.oidc declarations
#                   (catches a route added without a rebuild on pi).
#
# Runtime-introspection test: authelia live ↔ nori.lanRoutes.<X>.oidc declarations.
@test-authelia:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0

    host_self=$(hostname)
    flake_ref=".#nixosConfigurations.${host_self}.config"
    domain=$(nix eval --raw "${flake_ref}.nori.domain" 2>/dev/null)
    pi_tailnet=$(nix eval --raw "${flake_ref}.nori.hosts.pi.tailnetIp" 2>/dev/null)

    # Helpers — every probe lands on pi regardless of which host invoked
    # this recipe (authelia only runs there).
    pi_curl() {
      if [[ "$host_self" == "pi" ]]; then curl -s "$@"
      else ssh -o ConnectTimeout=3 "nori@${pi_tailnet}" "curl -s $*"
      fi
    }
    pi_ssh() {
      if [[ "$host_self" == "pi" ]]; then bash -c "$*"
      else ssh -o ConnectTimeout=3 "nori@${pi_tailnet}" "$*"
      fi
    }

    echo "=== Tier 1 — authelia-main.service active on pi ==="
    active=$(pi_ssh "systemctl is-active authelia-main.service" 2>/dev/null || echo "unknown")
    if [[ "$active" == "active" ]]; then
      echo "  ✓ active"
    else
      echo "  ✗ $active"; fail=1
    fi

    echo "=== Tier 2 — /api/health on loopback ==="
    health=$(pi_curl http://127.0.0.1:9091/api/health 2>/dev/null || echo "")
    if echo "$health" | grep -qi 'ok'; then
      echo "  ✓ OK"
    else
      echo "  ✗ health=$health"; fail=1
    fi

    echo "=== Tier 3 — OIDC discovery via caddy ==="
    issuer_expected="https://auth.${domain}"
    meta=$(curl -fsS -m 4 "${issuer_expected}/.well-known/openid-configuration" 2>/dev/null || echo "{}")
    issuer_actual=$(echo "$meta" | nix shell nixpkgs#jq -c jq -r '.issuer // ""' 2>/dev/null)
    if [[ "$issuer_actual" == "$issuer_expected" ]]; then
      echo "  ✓ issuer=$issuer_actual"
    else
      echo "  ✗ issuer=$issuer_actual (expected $issuer_expected)"; fail=1
    fi

    echo "=== Tier 4 — sops secrets for every declared OIDC route present + non-empty ==="
    # Authelia config validation rejects empty/malformed secrets at
    # startup, so if Tier 1 passed, the secrets evaluated OK. But the
    # *files* in /run/secrets can desync after a sops updatekeys race;
    # this tier catches that class. One file per declared OIDC route
    # (raw client-secret + PBKDF2 hash).
    declared_oidc=$(nix eval --raw "${flake_ref}.nori.lanRoutes" \
                      --apply 'r: builtins.concatStringsSep " " (builtins.filter (n: r.${n}.oidc != null) (builtins.attrNames r))' 2>/dev/null)
    for route in $declared_oidc; do
      for kind in client-secret client-secret-hash; do
        path="/run/secrets/oidc-${route}-${kind}"
        sz=$(pi_ssh "stat -c '%s' '$path' 2>/dev/null || echo 0")
        if [[ "$sz" -gt 0 ]]; then
          echo "  ✓ oidc-${route}-${kind} ($sz bytes)"
        else
          echo "  ✗ oidc-${route}-${kind} missing or empty"; fail=1
        fi
      done
    done

    echo
    [[ "$fail" -eq 0 ]] && echo "=== ALL PASS ===" || { echo "=== FAIL ==="; exit 1; }

# Verifies every declared backup actually exists at the systemd +
# restic layers. Tier 1 = unit existence (declared → systemd registry).
# Tier 2 = last run was successful (declared → ran cleanly). Tier 3 =
# per-repo most-recent snapshot is fresh (declared → restic actually
# wrote data). Catches timer/service generation drift after Pattern C2
# changes, the prepareCommand race we hit 2026-06-07 (dual-target + no
# flock), and missing OnFailure → notify@ wiring (silent alerting gap).
#
# Runtime-introspection test: every `nori.backups.<X>` has a fresh snapshot on every declared target.
@test-backups:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    pass=0

    # Names that have actual restic backups (runtime side of the
    # nori.backups registry — equivalent to filtering nix-side for
    # `include != null` but a single systemd query is cheaper).
    repos=$(systemctl list-units 'restic-backups-*.service' --all --no-pager 2>&1 \
            | grep -oE 'restic-backups-[a-z-]+\.service' \
            | sed 's/restic-backups-//; s/-onetouch.service//; s/-mp510.service//' \
            | sort -u)

    echo "=== Tier 1 — restic units exist in the registry ==="
    units=$(systemctl list-unit-files 'restic-backups-*.service' --no-pager 2>&1 \
            | grep -oE 'restic-backups-[a-z-]+\.service' | sort -u)
    n_units=$(echo "$units" | wc -l)
    echo "  ✓ $n_units restic-target units in registry"

    echo "=== Tier 2 — fresh snapshot per repo per target (25h window) ==="
    # ExecMainStatus=0 is a misleading proxy — it doesn't reflect
    # ExecStartPre (prepareCommand) failures, which is exactly the
    # race shape that caught us 2026-06-07. Snapshot freshness IS the
    # canonical truth: if a fresh snapshot exists, the backup ran
    # end-to-end successfully — pre, main, post, all of it.
    #
    # Restic repo mountpoints by target:
    #   onetouch → /mnt/backup/<repo>       (OneTouch, ext4, SFTP on aurora)
    #   mp510    → /mnt/backup-local/<repo> (MP510 NVMe @backup-local, btrfs)
    snapshot_age() {
      local repo="$1" mount="$2"
      # `--latest 1` returns ONE PER PATH-SET, not per repo (caught
      # 2026-06-07; led to 801h false positives). Take all, sort by
      # time, pick last.
      sudo RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
        nix shell nixpkgs#restic -c restic -r "$mount/$repo" \
          snapshots --json 2>/dev/null \
        | nix shell nixpkgs#jq -c jq -r 'sort_by(.time) | .[-1].time // ""' 2>/dev/null || true
    }

    for repo in $repos; do
      for target in onetouch mp510; do
        echo "$units" | grep -q "restic-backups-${repo}-${target}.service" || continue
        mount="/mnt/backup"
        [[ "$target" == "mp510" ]] && mount="/mnt/backup-local"
        latest=$(snapshot_age "$repo" "$mount")
        if [[ -z "$latest" ]]; then
          echo "  · $repo/$target: no snapshots yet"; continue
        fi
        age_h=$(( ($(date +%s) - $(date -d "$latest" +%s 2>/dev/null || echo 0)) / 3600 ))
        if [[ "$age_h" -le 25 ]]; then
          echo "  ✓ $repo/$target: ${age_h}h"
        else
          echo "  ✗ $repo/$target: ${age_h}h (>25h)"; fail=1
        fi
      done
    done

    echo
    [[ "$fail" -eq 0 ]] && echo "=== ALL PASS ===" || { echo "=== FAIL ==="; exit 1; }

# Each `nori.replicas.<X>` declares a cross-host dataset replica with
# a freshness budget. The verifier (modules/effects/replication.nix)
# emits a per-replica oneshot on the target host; this test reads the
# registry, finds entries targeting THIS host, and asserts each
# verifier unit completed cleanly within the freshness budget.
#
# Smoke gate: zero replicas declared (current state until P15 lands the
# btrfs send/receive timer) exits 0 with "no replicas declared". When
# P15 wires aurora → workstation MP510, this lever starts catching
# stalled receives without waiting for the next ntfy alert.
#
# Runtime-introspection test: `nori.replicas.<X>` → fresh snapshot on the target host.
@test-replicas:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0

    host=$(hostname)
    declared=$(nix eval --json ".#nixosConfigurations.${host}.config.nori.replicas" \
                 --apply 'r: builtins.attrNames (builtins.intersectAttrs r r)' 2>/dev/null \
               | nix shell nixpkgs#jq -c jq -r '.[]' 2>/dev/null || true)

    if [[ -z "$declared" ]]; then
      echo "=== test-replicas: no replicas declared (skipped) ==="
      exit 0
    fi

    echo "=== Replica freshness — entries targeting $host ==="
    for name in $declared; do
      target_host=$(nix eval --raw ".#nixosConfigurations.${host}.config.nori.replicas.${name}.target.host" 2>/dev/null)
      if [[ "$target_host" != "$host" ]]; then
        continue
      fi
      unit="replication-verifier-${name}.service"
      result=$(systemctl show -p Result --value "$unit" 2>/dev/null || echo "absent")
      if [[ "$result" == "success" ]]; then
        echo "  ✓ $name: verifier OK"
      elif [[ "$result" == "absent" ]]; then
        echo "  ✗ $name: verifier unit missing"; fail=1
      else
        echo "  ✗ $name: verifier Result=$result"; fail=1
      fi
    done

    echo
    [[ "$fail" -eq 0 ]] && echo "=== ALL PASS ===" || { echo "=== FAIL ==="; exit 1; }

# Smoke-test the Hyprland config we just deployed. Three tiers, each
# catching a different class of regression:
#
#   1. Syntax — `hyprctl reload` exit code (catches parse errors).
#   2. Dispatcher — each toggle_special invocation returns "ok"
#      (catches Hyprland-version-bump renames + lua-mode CLI traps
#      like the one that silently broke popup-term 2026-06-07).
#   3. Bind registry — `hyprctl binds -j` introspection: every
#      declared mod+key combo is registered (catches keymap drift
#      that tier 2 alone can't see).
#
# Each toggle test runs PAIRED (toggle on, toggle off) so the
# operator's session is left exactly as found — tests are
# non-destructive by construction.
#
# Runtime-introspection test: Hyprland syntax + dispatcher + bind registry.
@test-hypr:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0

    check() {
      local label="$1" expr="$2"
      out=$(hyprctl dispatch "$expr" 2>&1) || { echo "  ✗ $label (hyprctl errored)"; fail=1; return; }
      [[ "$out" == "ok" ]] || { echo "  ✗ $label — got: $out"; fail=1; return; }
      echo "  ✓ $label"
    }

    echo "=== Tier 1 — config parse ==="
    out=$(hyprctl reload 2>&1) && [[ "$out" == "ok" ]] && echo "  ✓ reload" || { echo "  ✗ reload: $out"; fail=1; }

    echo "=== Tier 2 — dispatcher smoke (paired toggles, net effect: zero) ==="
    for tag in browser term music notes comms files; do
      check "toggle special:$tag (on)"  "hl.dsp.workspace.toggle_special({ name = \"$tag\" })"
      check "toggle special:$tag (off)" "hl.dsp.workspace.toggle_special({ name = \"$tag\" })"
    done

    echo "=== Tier 3 — bind registry introspection ==="
    # Pivoted away from live keypress synthesis after research:
    #   * wtype + Hyprland keybinds is known-broken (issue
    #     hyprwm/Hyprland#6647) — virtual keyboard events get filtered
    #     somewhere in the bind matcher pipeline.
    #   * `hl.dsp.send_shortcut(...)` sends to a target window, NOT
    #     through the compositor bind matcher — wrong tool.
    #   * `ydotool` (uinput-level) would work but needs daemon +
    #     /dev/uinput perms + extra setup; not worth the complexity.
    #
    # Static introspection via `hyprctl binds -j` is strictly better:
    # deterministic, layout-independent, runs in <100ms, catches the
    # "I changed my mod combo and forgot to update lua" class of bug
    # that keypress synthesis would also catch — and a few that it
    # wouldn't (binds registered but pointing nowhere).
    #
    # Modmask bits: SHIFT=1, CTRL=4, ALT=8, LOGO/SUPER=64
    # SUPER+ALT = 64+8 = 72.

    binds_json=$(hyprctl binds -j)
    check_bind() {
      local label="$1" modmask="$2" key="$3"
      hit=$(echo "$binds_json" | nix shell nixpkgs#jq -c jq --argjson m "$modmask" --arg k "$key" \
        '[.[] | select(.modmask == $m and .key == $k)] | length')
      if [[ "$hit" -ge 1 ]]; then
        echo "  ✓ $label registered (modmask=$modmask key=$key)"
      else
        echo "  ✗ $label NOT registered (expected modmask=$modmask key=$key)"
        fail=1
      fi
    }
    for tag_n in 1 2 3 4 5 6; do
      check_bind "SUPER+ALT+$tag_n (toggle tag)"        72 "$tag_n"
      check_bind "SUPER+ALT+SHIFT+$tag_n (move to tag)" 73 "$tag_n"
    done
    check_bind "SUPER+RETURN (popup-term)" 64 "RETURN"

    echo
    if [[ "$fail" -eq 0 ]]; then
      echo "=== ALL PASS ==="
    else
      echo "=== FAIL ==="
      exit 1
    fi

# Wraps snowfallorg/nix-editor (-i: in-place). Preserves comments +
# style. Doesn't activate — pair with `just preview` to test, `just
# rebuild` to commit, or `git checkout` to revert.
#
# The repo is module-graph not single-file, so the operator picks
# the file — nix-editor is honest about its scope: it won't infer
# where in the import tree a brand-new attribute belongs.
#
# Quoting: shell-quote the whole value-expression so Nix-level quotes
# (for strings) survive. For complex exprs / attrsets, edit by hand.
#
# Usage:
#   just set modules/desktop/stylix.nix stylix.image '"${pkgs.nixos-artwork.wallpapers.dracula}/share/.../image.png"'
#   just set modules/services/blocky.nix services.blocky.enable false
#
# AST-splice a scalar into a `.nix` file, then run the project formatter. Complex exprs: edit by hand.
@set file attr value:
    # nix-editor's -f flag uses nixpkgs-fmt; project uses nixfmt via
    # nixfmt-tree (see flake.nix `formatter.${system} = pkgs.nixfmt-tree;`).
    # Skip -f and run `nix fmt` after to keep style consistent.
    nix run github:snowfallorg/nix-editor -- -i -v '{{value}}' '{{file}}' '{{attr}}'
    nix fmt -- '{{file}}'
    @echo "--- diff ---"
    @git --no-pager diff -- '{{file}}' | head -30
    @echo "--- next: just preview (try) → just rebuild (commit) — or git checkout '{{file}}' to revert ---"

# In-terminal search.nixos.org/options scoped to THIS flake's eval,
# not generic nixpkgs. Pass the dotted attribute path; trailing `.*`
# for everything under a prefix.
#
# Usage:
#   just show-option services.tailscale.enable
#   just show-option stylix.iconTheme.package
#
# Show a NixOS option from THIS flake's eval — type, default, current value, description.
@show-option path:
    @echo "=== type ===" && \
    nix eval --raw .#nixosConfigurations.$(hostname).options.{{path}}.type.description 2>/dev/null || echo "(unknown — wrong path?)"; \
    echo "=== default ===" && \
    nix eval .#nixosConfigurations.$(hostname).options.{{path}}.default 2>/dev/null || echo "(no default)"; \
    echo "=== current ===" && \
    nix eval .#nixosConfigurations.$(hostname).config.{{path}} 2>/dev/null || echo "(unset or computed)"; \
    echo "=== description ===" && \
    nix eval --raw .#nixosConfigurations.$(hostname).options.{{path}}.description 2>/dev/null || echo "(no description)"

# Activate at next boot only (for kernel/initrd changes).
@boot *args:
    nh os boot . -H $(hostname) {{args}}

# Roll back to the previous generation.
@rollback:
    sudo nixos-rebuild switch --rollback

# Build + activate from origin's main branch (no working-tree state).
# Useful for "deploy what's on github" without touching the local tree.
@deploy:
    nh os switch github:phibkro/homelab -H $(hostname)

# The operator's review surface for the push gate (CLAUDE.md § How to
# operate). Agents must run this (or `git log -p origin/main..HEAD`)
# before any `git push` and get explicit OK.
#
# Show local commits queued for push — full diff + subjects between `main` and `origin/main`.
@show-pending-diff:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! git log --oneline --no-decorate origin/main..HEAD | grep -q .; then
      echo "(none — local is at origin/main)"
      exit 0
    fi
    echo "=== commits queued for push ==="
    git log --oneline --no-decorate origin/main..HEAD
    echo
    echo "=== diff (via delta) ==="
    # delta = syntax-highlighted pager. Auto-narrows on mobile/SSH,
    # side-by-side on wide terminals. --paging=always forces the
    # pager even when piped (so operator can scroll on phone).
    git log -p --reverse origin/main..HEAD | delta --paging=always

# === validate ===

# Run nix flake check (statix + deadnix + nixfmt + eval) locally.
@check:
    nix --extra-experimental-features "nix-command flakes" flake check

# Migration-era one-off checks (path-coherence, multi-line-comments).
# Not part of nix flake check by design — they served the restructure
# phases and have near-nil catch-rate at steady state. Run on demand
# during restructures or when a long-running drift is suspected.
@check-migration:
    bash lint/checks/path-coherence.sh .
    bash lint/checks/multi-line-comments.sh .

# === e2e nixosTest helpers (per docs/reference/testing-methodology.md) ===

# Open the nixosTest driver interactively — boot the VM ONCE, iterate
# on testScript fragments without rebuilding. The big iteration-loop
# win for layer 2 (nixosTest) work. Default to e2e-pi-smoke; pass a
# different test name to open another driver.
@e2e-shell test="e2e-pi-smoke":
    nix run .#checks.x86_64-linux.{{test}}.driverInteractive

# Run all layer-1 eval tests — sub-second checks of schema +
# composition. Faster inner-loop than the layer-2 nixosTest. Each
# eval-* flake check evaluates a NixOS config in-process and asserts
# the resulting `config.<X>` shape.
@test-eval:
    nix --extra-experimental-features "nix-command flakes" \
      build --no-link --print-out-paths \
      $(nix --extra-experimental-features "nix-command flakes" \
        flake show --json 2>/dev/null | \
        nix shell nixpkgs#jq -c jq -r \
          '.checks."x86_64-linux" | to_entries | map(select(.key | startswith("eval-"))) | .[].key' | \
        sed 's|^|.#checks.x86_64-linux.|')

# Format all .nix files via the project formatter (nixfmt via nixfmt-tree).
@fmt:
    nix fmt

# Update flake.lock (re-pin inputs). Re-pinning unstable should be deliberate.
@update-flake:
    nix --extra-experimental-features "nix-command flakes" flake update

# === observe (local) ===

# Useful before adding a new service — confirms what's taken so the
# eval-time port-uniqueness assertion in modules/effects/lan-route.nix
# doesn't bite, and avoids the cascade-rebind dance when an upstream
# module's default happens to collide. Eval-only; safe from any tree.
# Defaults to workstation (where lanRoutes are declared; Pi's lanRoutes
# are gated on Caddy presence and so always empty).
#
# List ports claimed by `nori.lanRoutes` on a host, sorted by port. Eval-only.
@list-ports host=default_host:
    nix --extra-experimental-features "nix-command flakes" eval --raw \
        .#nixosConfigurations.{{host}}.config.nori.lanRoutes \
        --apply 'lr: let pairs = builtins.attrValues (builtins.mapAttrs (n: v: { name = n; port = v.port; }) lr); sorted = builtins.sort (a: b: a.port < b.port) pairs; in (builtins.concatStringsSep "\n" (map (e: "  ${toString e.port}\t${e.name}") sorted)) + "\n"'

# Quick health summary: failed units, disk usage, restic + btrbk timer state.
@show-status:
    echo "=== failed units ==="
    systemctl --failed --no-pager
    echo
    echo "=== disks ==="
    df -h / /mnt/media /mnt/backup 2>/dev/null || true
    echo
    echo "=== timers (restic + btrbk) ==="
    systemctl list-timers "restic-*" "btrbk-*" --no-pager 2>/dev/null || true

# Tail recent journal lines for a unit. Usage: just show-logs <unit>
@show-logs unit:
    sudo journalctl -u {{unit}} -n 50 --no-pager

# Live-tail a unit. Usage: just follow <unit>
@follow unit:
    sudo journalctl -u {{unit}} -f

# Pi tailnet IP is hardcoded — stable, avoids an extra nix-eval per
# invocation. See .claude/skills/query-logs/SKILL.md for syntax.
#
# Usage:
#   just query-logs 'unit:ollama.service priority:<=3 | head 20'
#   just query-logs 'level:error | _time:1h | stats by (unit) count()'
#
# Query the central VictoriaLogs index via LogsQL. Cross-host, fan-out included.
@query-logs query:
    curl -sG "http://100.100.71.3:9428/select/logsql/query" \
        --data-urlencode 'query={{query}}' \
      | (command -v jq >/dev/null && jq . || cat)

# === backup ===

# Repos: user-data | media-irreplaceable | open-webui | etc.
# Usage: just backup <repo>
#
# Trigger an immediate backup of a repo (out-of-cycle from the scheduled timer).
@backup repo:
    sudo systemctl start restic-backups-{{repo}}.service && journalctl -u restic-backups-{{repo}}.service -f

# Trigger restic check now (weekly cadence is automatic via systemd timer).
@check-restic:
    sudo systemctl start restic-check-weekly.service && journalctl -u restic-check-weekly.service -f

# Three tiers split by cost + cadence; `services` is cheap and fast,
# `user-data` is the heavy one, `all` includes media-irreplaceable
# (multi-hour). Usage: just restore-drill [services|user-data|all]
#
# Verify backups are *restorable* (not just *recorded*) by replaying the latest snapshot.
@restore-drill tier="services":
    sudo systemctl start restore-drill-{{tier}}.service && journalctl -u restore-drill-{{tier}}.service -f

# List restic snapshots for a repo. Usage: just list-snapshots <repo>
@list-snapshots repo:
    sudo /run/current-system/sw/bin/restic -r /mnt/backup/{{repo}} --password-file /run/secrets/restic-password snapshots

# === auth ===

# Output is sensitive — copy both YAML lines, paste into
# `sops secrets/secrets.yaml`, then `just rebuild`.
# Usage: just generate-oidc-key <name>
#
# Generate raw + PBKDF2 hash for a new lan-route OIDC client; print two paste-ready sops YAML lines.
@generate-oidc-key name:
    nix shell nixpkgs#openssl nixpkgs#authelia --command bash scripts/generate-oidc-key.sh {{name}}

# === ssh — explicit cross-host shell ===

# Drop into another host's shell.
@ssh host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}}

# === doc quality ===

# Reading the whole doc to find the right section is wasteful when
# the `## ` headings already index it. Pair with the editor / Read
# tool to load only the relevant section.
# Usage: just generate-toc gotchas | just generate-toc architecture
#
# Generate a table-of-contents from a doc's `## ` section headings — entry-point into long docs.
@generate-toc doc:
    grep '^## ' docs/{{doc}}.md | sed 's/^## /  /'

# Each app's modules/services/<name>.nix declares a `<name>-build.
# service` oneshot — this recipe just kicks it. Operator triggers
# explicitly so nixos-rebuild stays fast (no npm-install on every
# rebuild). Logs stream live, exit code matches the unit's.
# Usage: just deploy-app filmder
#
# Build + publish a personal app's static artifact via its `<name>-build.service` oneshot.
deploy-app name:
    sudo systemctl start --wait {{name}}-build.service
    @echo ""
    @echo "[deploy-app {{name}}] Last 20 log lines:"
    @journalctl -u {{name}}-build.service --no-pager -n 20

# Measures whether session wrap-ups left enough context for a fresh
# agent to perform — closes the otherwise-open loop on the "On every
# structural change" / "On session end" rubrics. See
# docs/agent-onboarding-test.md.
# Run after major refactors or when the user pushes back on doc clarity.
#
# Test a fresh agent's onboarding: print the prompt to dispatch through the orientation drill.
@test-agent-onboarding:
    @echo "Onboarding test — dispatch a fresh subagent (or fresh Claude session) with:"
    @echo ""
    @echo "  You are a fresh agent with zero prior context on this homelab project."
    @echo "  Read CLAUDE.md first to orient. Then for each numbered question in"
    @echo "  docs/agent-onboarding-test.md, give a terse answer (~3 bullets)"
    @echo "  using only files reachable from CLAUDE.md's routing table. Cite the"
    @echo "  source file. Don't read the 'Expected (shape)' sections until AFTER"
    @echo "  you've answered — those are grading rubrics, not hints."
    @echo ""
    @echo "Then compare answers to 'Expected (shape)' in each question. Failures:"
    @echo "  - knowledge gap (info missing)"
    @echo "  - routing gap (info exists but unreachable from CLAUDE.md)"
    @echo "  - foregrounding gap (reachable but not where the agent looks first)"
    @echo ""
    @echo "Fix the gap and re-run."
