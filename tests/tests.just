#!/usr/bin/env just --justfile
# Test recipes extracted from the root Justfile (2026-06-21) to keep
# the top-level file focused on build/deploy/observe verbs.
#
# Imported via `import 'tests.just'` in Justfile — recipes appear at
# top level (no `tests::` namespace prefix). Same variable scope as
# the root Justfile.
#
# Layer mix:
#   * Runtime-introspection (layer 3): test-{harden,fs,routes,backups,
#     replicas,authelia,observability,hypr} — query live state against
#     declared intent on this host.
#   * Eval (layer 1): test-eval runs every eval-* flake check (sub-sec).
#   * Composite (test): runs all of the above in one signal (~3 min).
#   * Process: test-agent-onboarding is a meta-test for doc orientation.
#
# Adding a new test-<X>: drop it here, add it to the `test` composite
# below if it should run as part of the standard suite. The flake
# check `infra-concerns-have-tests` (flake.nix) enforces that any new
# Reader-shaped infra concern has a matching recipe — that check
# greps for `^@?test-<X>:` in Justfile and walks `import` lines, so
# tests.just is in-scope.

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
# Composite: all runtime-introspection recipes + the eval suite.
# ~3 min wall, one signal. Includes `test-eval` so `just test` locally
# matches what CI's `nix flake check` covers (eval tests are sub-second;
# the layer mix is intentional — verifying intent at every layer in
# one command).
@test:
    just test-hypr
    just test-backups
    just test-routes
    just test-observability
    just test-replicas
    just test-authelia
    just test-harden
    just test-fs
    just test-eval

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

# Every `nori.harden.<unit>` declares a filesystem-namespace hardening
# profile (binds, readOnlyBinds, protectHome). The flake check
# `every-service-has-fs-hardening` enforces declaration; this recipe
# verifies the declaration LANDED in the live unit's serviceConfig.
# Catches mkForce-precedence drift, nori.fs path renames the harden
# block didn't catch, and unit-name-vs-declaration drift.
#
# Runtime-introspection test: every declared nori.harden.<unit> matches live systemd serviceConfig.
@test-harden:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    pass=0
    skipped=0

    host=$(hostname)
    echo "=== test-harden on $host ==="

    declared=$(nix eval ".#nixosConfigurations.$host.config.nori.harden" --json 2>/dev/null) || {
      echo "  ✗ failed to eval nori.harden for $host"
      exit 1
    }
    n_units=$(echo "$declared" | nix shell nixpkgs#jq -c jq 'length')
    echo "  ✓ $n_units declared nori.harden entries"

    echo
    echo "=== Tier 2 — declared binds + readOnlyBinds present in live systemd ==="
    # Live values via systemctl show -p; declared paths via jq.
    # Compare on substring (live BindPaths is "src:dst:opts" form).
    for unit in $(echo "$declared" | nix shell nixpkgs#jq -c jq -r 'keys[]'); do
      if ! systemctl cat "$unit.service" > /dev/null 2>&1; then
        skipped=$((skipped + 1))
        continue
      fi

      live_bind=$(systemctl show "$unit.service" -p BindPaths --value 2>/dev/null || echo "")
      live_robind=$(systemctl show "$unit.service" -p BindReadOnlyPaths --value 2>/dev/null || echo "")

      for b in $(echo "$declared" | nix shell nixpkgs#jq -c jq -r ".\"$unit\".binds[]?"); do
        if echo "$live_bind" | grep -q "$b"; then
          pass=$((pass + 1))
        else
          echo "  ✗ $unit: declared bind '$b' missing from live BindPaths"
          fail=1
        fi
      done
      for b in $(echo "$declared" | nix shell nixpkgs#jq -c jq -r ".\"$unit\".readOnlyBinds[]?"); do
        if echo "$live_robind" | grep -q "$b"; then
          pass=$((pass + 1))
        else
          echo "  ✗ $unit: declared readOnlyBind '$b' missing from live BindReadOnlyPaths"
          fail=1
        fi
      done
    done

    echo
    echo "  $pass bind checks passed; $skipped units not deployed on this host"
    [[ "$fail" -eq 0 ]] && echo "=== ALL PASS ===" || { echo "=== FAIL ==="; exit 1; }

# Every `nori.fs.<n>` declares a named filesystem location with a value
# tier. The test asserts: (a) the declared path exists on disk, and
# (b) every tier=irreplaceable path is covered by a `nori.backups.<X>`
# entry. The second is the load-bearing check — silent missed-backup
# coverage on irreplaceable data is the worst failure mode in the lab.
#
# Runtime-introspection test: declared nori.fs paths exist + irreplaceable tier has backup coverage.
@test-fs:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    pass=0

    host=$(hostname)
    echo "=== test-fs on $host ==="

    fs=$(nix eval ".#nixosConfigurations.$host.config.nori.fs" --json 2>/dev/null) || {
      echo "  ✗ failed to eval nori.fs for $host"
      exit 1
    }
    backups=$(nix eval ".#nixosConfigurations.$host.config.nori.backups" --json 2>/dev/null || echo '{}')
    n_fs=$(echo "$fs" | nix shell nixpkgs#jq -c jq 'length')
    echo "  ✓ $n_fs declared nori.fs entries"

    echo
    echo "=== Tier 1 — declared paths exist on disk ==="
    for name in $(echo "$fs" | nix shell nixpkgs#jq -c jq -r 'keys[]'); do
      path=$(echo "$fs" | nix shell nixpkgs#jq -c jq -r ".\"$name\".path")
      if [[ -e "$path" ]]; then
        pass=$((pass + 1))
      else
        echo "  ✗ $name: declared path '$path' not present on disk"
        fail=1
      fi
    done

    echo
    echo "=== Tier 2 — irreplaceable tier covered by a backup include ==="
    # Flatten every backup's include list into one set of covered paths.
    covered=$(echo "$backups" | nix shell nixpkgs#jq -c jq -r '[.[] | .include // [] | .[]] | unique | .[]?')

    for name in $(echo "$fs" | nix shell nixpkgs#jq -c jq -r 'to_entries[] | select(.value.tier == "irreplaceable") | .key'); do
      path=$(echo "$fs" | nix shell nixpkgs#jq -c jq -r ".\"$name\".path")
      if echo "$covered" | grep -qxF "$path"; then
        pass=$((pass + 1))
      else
        # Check if any covered path is a prefix (e.g. /mnt/family covers /mnt/family/photos)
        if echo "$covered" | while IFS= read -r cov; do
            [[ -n "$cov" ]] && [[ "$path" == "$cov"* ]] && exit 100
          done; [[ $? -eq 100 ]]; then
          pass=$((pass + 1))
        else
          echo "  ✗ $name (tier=irreplaceable, $path) — no covering nori.backups include"
          fail=1
        fi
      fi
    done

    echo
    echo "  $pass checks passed"
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
