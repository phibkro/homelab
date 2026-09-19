#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
readonly script_dir repo_root

fixture="$script_dir/fixtures/inventory.json"
fake_bin="$(mktemp -d)"
output="$(mktemp)"
unsafe_fixture="$(mktemp)"
same_port_fixture="$(mktemp)"
collision_fixture="$(mktemp)"
string_paths_fixture="$(mktemp)"
inactive_exporters_fixture="$(mktemp)"
inactive_beszel_fixture="$(mktemp)"
beszel_port_fixture="$(mktemp)"
cleanup() {
  rm -rf "$fake_bin" "$output" "$unsafe_fixture" "$same_port_fixture" \
    "$collision_fixture" "$string_paths_fixture" "$inactive_exporters_fixture" \
    "$inactive_beszel_fixture" "$beszel_port_fixture"
}
trap cleanup EXIT

cp "$script_dir/fixtures/nix" "$fake_bin/nix"
chmod 0755 "$fake_bin/nix"

PATH="$fake_bin:$PATH" \
  INVENTORY_FIXTURE="$fixture" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null

jq --exit-status --slurpfile source "$fixture" '
  .pi_appliances.hosts.pi as $pi
  | $pi.pi_backup_enabled == true
    and $pi.pi_backup_target_address == $source[0].hosts.workstation.tailnetIp
    and $pi.pi_backup_target_host == $source[0].backup.hostname
    and $pi.pi_backup_target_user == $source[0].backup.pi.user
    and $pi.pi_backup_repository_prefix == $source[0].backup.pi.repositoryPrefix
    and $pi.pi_backup_target_known_host == ($source[0].backup.hostname + " " + $source[0].backup.pi.hostKey)
    and $pi.pi_backup_jobs == $source[0].backup.pi.jobs
' "$output" >/dev/null

jq --exit-status '
  (.pi_appliances.hosts | keys) == ["pi"]
  and .pi_appliances.hosts.pi.pi_routes == [
    {
      name: "pihole",
      hostname: "pihole.home.example",
      upstream_address: "192.168.1.225",
      upstream_port: 8081,
      scheme: "http",
      reachability: "internal",
      audience: "operator",
      auth: "none",
      forward_auth_exempt_paths: [],
      forward_auth_upstream: null,
      oidc_redirect_path: null,
      upstream_host_header: null,
      upstream_origin_header: null
    },
    {
      name: "auth",
      hostname: "auth.home.example",
      upstream_address: "192.168.1.225",
      upstream_port: 9091,
      scheme: "http",
      reachability: "internal",
      audience: "public",
      auth: "none",
      forward_auth_exempt_paths: [],
      forward_auth_upstream: "192.168.1.225:9091",
      oidc_redirect_path: null,
      upstream_host_header: null,
      upstream_origin_header: null
    },
    {
      name: "books",
      hostname: "books.home.example",
      upstream_address: "100.81.5.122",
      upstream_port: 8084,
      scheme: "http",
      reachability: "internal",
      audience: "family",
      auth: "forward-auth",
      forward_auth_exempt_paths: ["/api/*"],
      forward_auth_upstream: "192.168.1.225:9091",
      oidc_redirect_path: null,
      upstream_host_header: null,
      upstream_origin_header: null
    },
    {
      name: "cache",
      hostname: "cache.home.example",
      upstream_address: "100.81.5.122",
      upstream_port: 5000,
      scheme: "http",
      reachability: "internal",
      audience: "operator",
      auth: "none",
      forward_auth_exempt_paths: [],
      forward_auth_upstream: "192.168.1.225:9091",
      oidc_redirect_path: null,
      upstream_host_header: null,
      upstream_origin_header: null
    },
    {
      name: "media",
      hostname: "media.home.example",
      upstream_address: "100.81.5.122",
      upstream_port: 8096,
      scheme: "http",
      reachability: "internet",
      audience: "family",
      auth: "none",
      forward_auth_exempt_paths: [],
      forward_auth_upstream: "192.168.1.225:9091",
      oidc_redirect_path: null,
      upstream_host_header: null,
      upstream_origin_header: null
    },
    {
      name: "photos",
      hostname: "photos.home.example",
      upstream_address: "100.81.5.122",
      upstream_port: 2283,
      scheme: "http",
      reachability: "internal",
      audience: "family",
      auth: "oidc",
      forward_auth_exempt_paths: [],
      forward_auth_upstream: "192.168.1.225:9091",
      oidc_redirect_path: "/auth/login",
      upstream_host_header: null,
      upstream_origin_header: null
    }
  ]
  and (.pi_appliances.hosts.pi.pi_routes | length == 6)
  and .pi_appliances.hosts.pi.ddns_hostnames == ["media.home.example"]
  and .pi_appliances.hosts.pi.pi_deprecated_domains == ["nori.lan"]
  and (.pi_appliances.hosts.pi.pihole_local_dns_records
       | any(.[]; .names[] == "books.home.example"))
  and (.pi_appliances.hosts.pi.pihole_local_dns_records
       | any(.[]; .names[] == "pihole.nori.lan"))
  and (.pi_appliances.hosts.pi.pihole_local_dns_records
       | all(.[]; .address == "192.168.1.225" or .address == "192.168.1.181"))
  and ([.pi_appliances.hosts.pi.pihole_local_dns_records[] | .names[]]
       | length == (unique | length))
' "$output" >/dev/null

jq --exit-status '
  .pi_appliances.hosts.pi.authelia_oidc_clients == [
    {
      client_id: "photos",
      client_name: "Immich",
      authorization_policy: "one_factor",
      token_endpoint_auth_method: "client_secret_post",
      redirect_uris: ["https://photos.home.example/auth/login"],
      scopes: ["openid", "profile", "email", "groups"]
    }
  ]
  and ([.pi_appliances.hosts.pi.gatus_endpoints[] | .name]
       | .[0:5]
       == ["pihole-dns", "pihole-admin", "station-blocky-dns", "station-ssh",
           "station-caddy"])
  and (.pi_appliances.hosts.pi.gatus_endpoints
       | any(.[]; .name == "auth"
                    and .url == "http://192.168.1.225:9091/api/health"
                    and .conditions == ["[STATUS] == 200"])
       and any(.[]; .name == "books"
                    and .url == "http://100.81.5.122:8084/"
                    and .interval == "60s")
       and any(.[]; .name == "cache"
                    and .url == "http://100.81.5.122:5000/"
                    and .interval == "60s")
       and any(.[]; .name == "media"
                    and .url == "http://100.81.5.122:8096/health"
                    and .failure_threshold == 5)
       and any(.[]; .name == "photos"
                    and .url == "http://100.81.5.122:2283/api/server/ping"
                    and .interval == "30s"))
  and .pi_appliances.hosts.pi.beszel_agent_listen_port == 45876
  and .pi_appliances.hosts.pi.beszel_systems == [
    {name: "pi", host: "192.168.1.225", port: 45876},
    {name: "workstation", host: "100.81.5.122", port: 45876}
  ]
  and .pi_appliances.hosts.pi.victoriametrics_scrape_jobs == [
    {
      job_name: "gatus",
      static_configs: [{targets: ["192.168.1.225:8082"]}]
    },
    {
      job_name: "victoriametrics",
      static_configs: [{targets: ["192.168.1.225:8428"]}]
    },
    {
      job_name: "node",
      static_configs: [
        {targets: ["100.81.5.122:9100"], labels: {host: "workstation"}}
      ]
    },
    {
      job_name: "process",
      static_configs: [
        {targets: ["100.81.5.122:9256"], labels: {host: "workstation"}}
      ]
    },
    {
      job_name: "nvidia-gpu",
      static_configs: [
        {targets: ["100.81.5.122:9835"], labels: {host: "workstation"}}
      ]
    }
  ]
' "$output" >/dev/null

echo "inventory generator phase-two contract: PASS"

echo "inventory generator contract: PASS"

jq 'del(.workloads.authelia)' "$fixture" >"$unsafe_fixture"
if PATH="$fake_bin:$PATH" INVENTORY_FIXTURE="$unsafe_fixture" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null 2>&1; then
  echo "inventory generator contract: forward-auth without Authelia was accepted" >&2
  exit 1
fi

echo "inventory generator safety contract: PASS"

# Reusing a backend port is safe when the upstream addresses differ.
jq '.workloads."calibre-web".endpoints.books.port = 9091' \
  "$fixture" >"$same_port_fixture"
PATH="$fake_bin:$PATH" INVENTORY_FIXTURE="$same_port_fixture" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null

# The same address and port would make Caddy's backend socket ambiguous.
jq '.workloads."calibre-web".endpoints.books.runsOn = "pi"
    | .workloads."calibre-web".endpoints.books.port = 9091' \
  "$fixture" >"$collision_fixture"
if PATH="$fake_bin:$PATH" INVENTORY_FIXTURE="$collision_fixture" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null 2>&1; then
  echo "inventory generator contract: duplicate backend socket was accepted" >&2
  exit 1
fi

echo "inventory generator socket-collision contract: PASS"

jq '.workloads."calibre-web".endpoints.books.forwardAuth.exemptPaths = "/api/*"' \
  "$fixture" >"$string_paths_fixture"
if PATH="$fake_bin:$PATH" INVENTORY_FIXTURE="$string_paths_fixture" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null 2>&1; then
  echo "inventory generator contract: string forward-auth paths were accepted" >&2
  exit 1
fi

echo "inventory generator path-shape contract: PASS"

jq '.workloads["node-exporter"].active = false
    | .workloads["nvidia-gpu-exporter"].active = false' \
  "$fixture" >"$inactive_exporters_fixture"
PATH="$fake_bin:$PATH" INVENTORY_FIXTURE="$inactive_exporters_fixture" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null
jq --exit-status '
  .pi_appliances.hosts.pi.victoriametrics_scrape_jobs == [
    {job_name: "gatus", static_configs: [{targets: ["192.168.1.225:8082"]}]},
    {job_name: "victoriametrics", static_configs: [{targets: ["192.168.1.225:8428"]}]}
  ]
' "$output" >/dev/null

echo "inventory generator inactive-exporter contract: PASS"
jq '.workloads["beszel-agent"].active = false' \
  "$fixture" >"$inactive_beszel_fixture"
PATH="$fake_bin:$PATH" INVENTORY_FIXTURE="$inactive_beszel_fixture" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null
jq --exit-status \
  '.pi_appliances.hosts.pi.beszel_systems == []' \
  "$output" >/dev/null

echo "inventory generator inactive-Beszel contract: PASS"
jq '.workloads["beszel-agent"].agentPort = 51234' \
  "$fixture" >"$beszel_port_fixture"
PATH="$fake_bin:$PATH" INVENTORY_FIXTURE="$beszel_port_fixture" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null
jq --exit-status '
  .pi_appliances.hosts.pi.beszel_agent_listen_port == 51234
  and all(.pi_appliances.hosts.pi.beszel_systems[]; .port == 51234)
' "$output" >/dev/null

echo "inventory generator Beszel-port contract: PASS"

for mutation in 'del(.backup)' 'del(.backup.enabled)' '.backup.enabled = "false"' '.backup.pi.hostKey = ""' '.backup.pi.repositoryPrefix = "/pi"' '.backup.pi.jobs = []' '.backup.targetHost = "missing"'; do
  jq "$mutation" "$fixture" >"$unsafe_fixture"
  if PATH="$fake_bin:$PATH" INVENTORY_FIXTURE="$unsafe_fixture" "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null 2>&1; then
    echo "inventory generator accepted invalid backup contract: $mutation" >&2
    exit 1
  fi
done
echo "inventory generator backup boundary: PASS"

# Explicit disabled intent means no backups. It must not emit connection inputs or
# a job manifest that could accidentally reactivate a production destination.
jq '.backup.enabled = false' "$fixture" >"$unsafe_fixture"
PATH="$fake_bin:$PATH" INVENTORY_FIXTURE="$unsafe_fixture" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null
jq --exit-status '
  .pi_appliances.hosts.pi
  | .pi_backup_enabled == false
    and ([keys[] | select(startswith("pi_backup_"))] == ["pi_backup_enabled"])
' "$output" >/dev/null
echo "inventory generator explicitly disabled backup boundary: PASS"
