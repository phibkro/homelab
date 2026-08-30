#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly repo_root
readonly output="${1:-$repo_root/pi/.devenv/state/generated-inventory.json}"
readonly ansible_user="${PI_ANSIBLE_USER:-nori}"

mkdir -p "$(dirname "$output")"

nix eval --json "$repo_root#lib.noriInventory" | jq \
  --arg ansible_user "$ansible_user" \
  '
    . as $inventory
    | $inventory.hosts.pi as $pi
    | $inventory.hosts.workstation as $station
    | $inventory.hosts.aurora as $aurora
    | $inventory.site.domain as $domain
    | $inventory.site.entryPlaneHost as $entry_plane_host
    | [
        $inventory.workloads
        | to_entries[]
        | select(.value.active != false)
        | . as $workload
        | (.value.endpoints // {})
        | to_entries[]
        | . as $endpoint
        | ($inventory.hosts[$endpoint.value.runsOn]) as $backend_host
        | {
            workload: $workload.key,
            name: $endpoint.key,
            endpoint: $endpoint.value,
            hostname: ($endpoint.key + "." + $domain),
            upstream_address: (
              if $endpoint.value.runsOn == $entry_plane_host
              then $pi.lanIp
              else $backend_host.tailnetIp
              end
            )
          }
      ] as $active_endpoints
    | ($active_endpoints | map({
        name: .name,
        hostname: .hostname,
        upstream_address: .upstream_address,
        upstream_port: .endpoint.port,
        scheme: (.endpoint.scheme // "http"),
        reachability: (.endpoint.reachability // "internal"),
        audience: (.endpoint.audience // "operator"),
        auth: (
          if .endpoint.forwardAuth != null then "forward-auth"
          elif .endpoint.oidc != null then "oidc"
          else "none"
          end
        ),
        forward_auth_exempt_paths: (.endpoint.forwardAuth.exemptPaths // []),
        forward_auth_upstream: ($pi.lanIp + ":9091"),
        oidc_redirect_path: (.endpoint.oidc.redirectPath // null),
        upstream_host_header: (.endpoint.upstreamHostHeader // null),
        upstream_origin_header: (.endpoint.upstreamOriginHeader // null)
      }) | sort_by(.name)) as $service_routes
    | (
        [
          {
            name: "pihole",
            hostname: ("pihole." + $domain),
            upstream_address: $pi.lanIp,
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
          }
        ] + $service_routes
      ) as $appliance_routes
    | ($active_endpoints
      | map(select(.endpoint.oidc != null) | {
          client_id: .name,
          client_name: .endpoint.oidc.clientName,
          authorization_policy: (.endpoint.oidc.authorizationPolicy // "one_factor"),
          redirect_uris: [
            ("https://" + .hostname + .endpoint.oidc.redirectPath)
          ],
          scopes: (.endpoint.oidc.scopes // ["openid", "profile", "email", "groups"])
        })
      | sort_by(.client_id)) as $oidc_clients
    | ($active_endpoints
      | map(select(.endpoint.monitor != null) | {
          name: .name,
          url: ((.endpoint.scheme // "http") + "://" + .upstream_address + ":"
            + (.endpoint.port | tostring)
            + (.endpoint.monitor.path // "/")),
          interval: (.endpoint.monitor.interval // "60s"),
          conditions: (.endpoint.monitor.conditions // ["[STATUS] == 200"]),
          failure_threshold: (.endpoint.monitor.failureThreshold // 3),
          send_on_resolved: true
        })
      | sort_by(.name)) as $route_probes
    | ([
        {
          name: "pihole-dns",
          url: ("tcp://" + $pi.lanIp + ":53"),
          interval: "60s",
          conditions: ["[CONNECTED] == true"]
        },
        {
          name: "pihole-admin",
          url: ("http://" + $pi.lanIp + ":8081/admin/"),
          interval: "60s",
          conditions: ["[STATUS] == 302"]
        },
        {
          name: "station-blocky-dns",
          url: ("tcp://" + $station.lanIp + ":53"),
          interval: "60s",
          conditions: ["[CONNECTED] == true"]
        },
        {
          name: "station-ssh",
          url: ("tcp://" + $station.lanIp + ":22"),
          interval: "60s",
          conditions: ["[CONNECTED] == true"]
        },
        {
          name: "station-caddy",
          url: ("https://uptime." + $domain),
          interval: "120s",
          conditions: ["[STATUS] == 200"]
        },
        {
          name: "aurora-ssh",
          url: ("tcp://" + $aurora.tailnetIp + ":22"),
          interval: "60s",
          conditions: ["[CONNECTED] == true"]
        },
        {
          name: "aurora-samba",
          url: ("tcp://" + $aurora.tailnetIp + ":445"),
          interval: "60s",
          conditions: ["[CONNECTED] == true"]
        }
      ] | map(. + {failure_threshold: 3, send_on_resolved: true})) as $explicit_probes
    | ([
        $inventory.hosts
        | to_entries[]
        | . as $host
        | select(
            ($inventory.workloads["node-exporter"].active != false)
            and (
              (($inventory.workloads["node-exporter"].hosts // []) | index($host.key)) != null
              or (($host.value.workloads // []) | index("node-exporter")) != null
            )
          )
        | {target: (.value.tailnetIp + ":9100"), host: .key}
      ]) as $node_hosts
    | ([
        $inventory.hosts
        | to_entries[]
        | . as $host
        | select(
            ($inventory.workloads["node-exporter"].active != false)
            and (
              (($inventory.workloads["node-exporter"].hosts // []) | index($host.key)) != null
              or (($host.value.workloads // []) | index("node-exporter")) != null
            )
          )
        | {target: (.value.tailnetIp + ":9256"), host: .key}
      ]) as $process_hosts
    | ([
        $inventory.hosts
        | to_entries[]
        | . as $host
        | select(
            ($inventory.workloads["nvidia-gpu-exporter"].active != false)
            and (
              (($inventory.workloads["nvidia-gpu-exporter"].hosts // []) | index($host.key)) != null
              or (($host.value.workloads // []) | index("nvidia-gpu-exporter")) != null
            )
          )
        | {target: (.value.tailnetIp + ":9835"), host: .key}
      ]) as $gpu_hosts
    | ([
        {
          job_name: "gatus",
          static_configs: [{targets: [($pi.lanIp + ":8082")]}]
        },
        {
          job_name: "victoriametrics",
          static_configs: [{targets: [($pi.lanIp + ":8428")]}]
        }
      ]
      + (if ($node_hosts | length) > 0 then [{
          job_name: "node",
          static_configs: [
            $node_hosts[] | {targets: [.target], labels: {host: .host}}
          ]
        }] else [] end)
      + (if ($process_hosts | length) > 0 then [{
          job_name: "process",
          static_configs: [
            $process_hosts[] | {targets: [.target], labels: {host: .host}}
          ]
        }] else [] end)
      + (if ($gpu_hosts | length) > 0 then [{
          job_name: "nvidia-gpu",
          static_configs: [
            $gpu_hosts[] | {targets: [.target], labels: {host: .host}}
          ]
        }] else [] end)) as $scrape_jobs
    | {
        pi_appliances: {
          hosts: {
            pi: {
              ansible_host: $pi.lanIp,
              ansible_user: $ansible_user,
              pi_lan_address: $pi.lanIp,
              pi_service_bind_address: $pi.lanIp,
              pihole_lan_address: $pi.lanIp,
              pihole_tailnet_address: $pi.tailnetIp,
              pi_domain: $domain,
              pi_deprecated_domains: $inventory.site.deprecatedDomains,
              pi_routes: $appliance_routes,
              authelia_oidc_clients: $oidc_clients,
              gatus_endpoints: ($explicit_probes + $route_probes),
              victoriametrics_scrape_jobs: $scrape_jobs,
              ddns_hostnames: [
                $service_routes[]
                | select(.reachability == "internet")
                | .hostname
              ],
              pihole_local_dns_records: (
                [
                  $inventory.hosts
                  | to_entries[]
                  | select(.value.lanIp != null)
                  | {
                      address: .value.lanIp,
                      names: [(.key + "." + $domain)]
                    }
                ]
                + [
                    $appliance_routes[] as $route
                    | {
                        address: $pi.lanIp,
                        names: (
                          [$route.hostname]
                          + [
                              $inventory.site.deprecatedDomains[]
                              | ($route.name + "." + .)
                            ]
                        )
                      }
                  ]
                | unique_by(.address + "|" + (.names | join("|")))
              )
            }
          }
        }
      }
  ' >"$output"

jq --exit-status \
  '.pi_appliances.hosts.pi.pi_lan_address as $pi_lan_address
   | .pi_appliances.hosts.pi.pi_routes as $routes
   | .pi_appliances.hosts.pi.ddns_hostnames as $ddns_hostnames
   | .pi_appliances.hosts.pi.authelia_oidc_clients as $oidc_clients
   | .pi_appliances.hosts.pi.gatus_endpoints as $gatus_endpoints
   | .pi_appliances.hosts.pi.victoriametrics_scrape_jobs as $scrape_jobs
   | ([$routes[] | select(.reachability == "internet") | .hostname]) as $expected_ddns_hostnames
   | .pi_appliances.hosts.pi.pi_lan_address != null
   and .pi_appliances.hosts.pi.pihole_lan_address == .pi_appliances.hosts.pi.pi_lan_address
   and .pi_appliances.hosts.pi.pihole_tailnet_address != null
   and (.pi_appliances.hosts | keys == ["pi"])
   and (.pi_appliances.hosts.pi.pi_routes | length > 1)
   and ([ $routes[] | .name ] | unique | length == ($routes | length))
   and ([ $routes[] | .hostname ] | unique | length == ($routes | length))
   and (.pi_appliances.hosts.pi.pi_routes[0].hostname
        == ("pihole." + .pi_appliances.hosts.pi.pi_domain))
   and (all(.pi_appliances.hosts.pi.pi_routes[];
        (.name | test("^[a-z][a-z0-9-]*$"))
        and (.hostname | test("^[a-z][a-z0-9-]*\\.[a-z0-9.-]+$"))
        and ((.upstream_address | type) == "string" and (.upstream_address | length) > 0)
        and (.upstream_port | tonumber > 0 and tonumber < 65536)
        and (.scheme == "http" or .scheme == "https")
        and (.reachability == "internal" or .reachability == "internet")
        and (.audience == "operator" or .audience == "family" or .audience == "public")
        and (.auth == "none" or .auth == "oidc" or .auth == "forward-auth")
      ))
   and (all(.pi_appliances.hosts.pi.pi_routes[];
        .reachability != "internet" or .audience != "operator"
      ))
   and (all(.pi_appliances.hosts.pi.pi_routes[];
        .auth != "forward-auth" or (.forward_auth_exempt_paths | type == "array")
      ))
   and (all(.pi_appliances.hosts.pi.pi_routes[]; .auth == "none")
        or any($routes[];
          .name == "auth"
          and .upstream_port == 9091
          and .upstream_address == $pi_lan_address
        ))
   and (all(.pi_appliances.hosts.pi.pi_routes[];
        .reachability != "internet" or .auth == "none"
        or any($routes[];
          .name == "auth" and .reachability == "internet"
        )
      ))
   and (.pi_appliances.hosts.pi.pi_deprecated_domains | type == "array")
   and ($oidc_clients | type == "array")
   and ([ $oidc_clients[] | .client_id ] | unique | length == ($oidc_clients | length))
   and (all($oidc_clients[];
        (.client_id | type == "string" and test("^[A-Za-z0-9._-]+$"))
        and (.client_name | type == "string" and length > 0)
        and (.authorization_policy | type == "string" and length > 0)
        and (.redirect_uris | type == "array" and length > 0)
        and all(.redirect_uris[]; type == "string" and test("^https://[a-z0-9.-]+/"))
        and (.scopes | type == "array" and length > 0)
        and all(.scopes[]; type == "string" and length > 0)
      ))
   and (([$oidc_clients[] | .client_id] | sort)
        == ([$routes[] | select(.auth == "oidc") | .name] | sort))
   and ($gatus_endpoints | type == "array" and length >= 7)
   and ([ $gatus_endpoints[] | .name ] | unique | length == ($gatus_endpoints | length))
   and (all($gatus_endpoints[];
        (.name | type == "string" and test("^[a-z][a-z0-9-]*$"))
        and (.url | type == "string" and test("^(https?://[^ ]+|tcp://[^ ]+:[0-9]+)$"))
        and (.interval | type == "string" and length > 0)
        and (.conditions | type == "array" and length > 0)
        and all(.conditions[]; type == "string" and length > 0)
        and (.failure_threshold | tonumber > 0)
        and (.send_on_resolved | type == "boolean")
      ))
   and (all(["pihole-dns", "pihole-admin", "station-blocky-dns", "station-ssh", "station-caddy", "aurora-ssh", "aurora-samba"][];
        . as $required | any($gatus_endpoints[]; .name == $required)
      ))
   and ($scrape_jobs | type == "array" and length >= 1)
   and ([ $scrape_jobs[] | .job_name ] | unique | length == ($scrape_jobs | length))
   and (any($scrape_jobs[]; .job_name == "gatus"
        and (.static_configs | type == "array" and length == 1)
        and (.static_configs[0].targets == [($pi_lan_address + ":8082")])))
   and (any($scrape_jobs[]; .job_name == "victoriametrics"
        and .static_configs[0].targets == [($pi_lan_address + ":8428")]))
   and (all($scrape_jobs[];
        (.job_name | type == "string" and test("^[a-z][a-z0-9-]*$"))
        and (.static_configs | type == "array" and length > 0)
        and all(.static_configs[];
          (.targets | type == "array" and length > 0)
          and all(.targets[]; type == "string" and test("^[0-9]+(\\.[0-9]+){3}:[0-9]+$"))
        )
      ))
   and ([ $routes[] | (.upstream_address + ":" + (.upstream_port | tostring)) ]
        | unique | length == ($routes | length))
   and ($ddns_hostnames == $expected_ddns_hostnames)
   and ([.pi_appliances.hosts.pi.pihole_local_dns_records[] | .names[]]
        | length == (unique | length))' \
  "$output" >/dev/null

printf '%s\n' "$output"
