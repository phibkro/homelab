#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
readonly repo_root
readonly output="${1:-$repo_root/infra/pi/.devenv/state/generated-inventory.json}"
readonly ansible_user="${PI_ANSIBLE_USER:-nori}"

mkdir -p "$(dirname "$output")"

nix eval --json "$repo_root#lib.noriInventory" | jq \
  --arg ansible_user "$ansible_user" \
  '
    if (.backup.enabled | type) != "boolean" then error("backup.enabled must be an explicit boolean") else . end
    | . as $inventory
    | $inventory.hosts.pi as $pi
    | $inventory.hosts.workstation as $station
    | $inventory.backup as $backup
    | $inventory.hosts[$backup.targetHost] as $backup_host
    | $inventory.site.domain as $domain
    | $inventory.site.entryPlaneHost as $entry_plane_host
    | $inventory.workloads["beszel-agent"].listenPort as $beszel_agent_port
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
    | ($active_endpoints
      | map(
          select(
            .endpoint.runsOn == $entry_plane_host
            and (.endpoint.exposeOnTailnet // false)
          )
          | .endpoint.port
        )
      | unique
      | sort) as $tailnet_workload_ports
    | ["Consume", "Acquire", "Personal", "Projects", "Admin"] as $dashboard_group_order
    | ($active_endpoints
      | map(select(.endpoint.dashboard != null) | {
          group: .endpoint.dashboard.group,
          title: .endpoint.dashboard.title,
          icon: .endpoint.dashboard.icon,
          description: .endpoint.dashboard.description,
          url: ("https://" + .hostname)
        })
      | group_by(.group)
      | map({
          title: .[0].group,
          links: (map(del(.group)) | sort_by(.title))
        })
      | sort_by(
          .title as $title
          | (($dashboard_group_order | index($title)) // 999),
          .title
        )) as $glance_bookmark_groups
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
          token_endpoint_auth_method: .endpoint.oidc.tokenEndpointAuthMethod,
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
          headers: (
            if (.endpoint.monitor.routeHostHeader // false)
            then {Host: .hostname}
            elif .endpoint.upstreamHostHeader != null
            then {Host: .endpoint.upstreamHostHeader}
            else {}
            end
          ),
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
          conditions: ["[STATUS] == 200"]
        },
        {
          name: "station-ssh",
          url: ("tcp://" + $station.lanIp + ":22"),
          interval: "60s",
          conditions: ["[CONNECTED] == true"]
        },
        {
          name: "entry-caddy",
          url: ("http://" + $pi.lanIp),
          interval: "120s",
          client: {"ignore-redirect": true},
          conditions: ["[STATUS] == 308"]
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
    | ((if $inventory.workloads["beszel-agent"].active != false then [
        ($inventory.workloads["beszel-agent"].hosts // [])[] as $host_name
        | $inventory.hosts[$host_name] as $host
        | {
            name: $host_name,
            host: (
              if $host_name == $entry_plane_host and $host.lanIp != null
              then $host.lanIp
              else $host.tailnetIp
              end
            ),
            port: $beszel_agent_port
          }
      ] else [] end) | sort_by(.name)) as $beszel_systems
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
              pi_backup_enabled: $backup.enabled,
              pi_backup_target_address: $backup_host.tailnetIp,
              pi_backup_target_host: $backup.hostname,
              pi_backup_target_user: $backup.pi.user,
              pi_backup_repository_prefix: $backup.pi.repositoryPrefix,
              pi_backup_target_known_host: ($backup.hostname + " " + $backup.pi.hostKey),
              pi_backup_jobs: $backup.pi.jobs,
              pi_domain: $domain,
              pi_deprecated_domains: $inventory.site.deprecatedDomains,
              pi_routes: $appliance_routes,
              pi_tailnet_workload_ports: $tailnet_workload_ports,
              glance_enabled: (
                $inventory.workloads.glance.active != false
                and any($inventory.workloads.glance.hosts[]; . == $entry_plane_host)
              ),
              glance_bookmark_groups: $glance_bookmark_groups,
              authelia_oidc_clients: $oidc_clients,
              gatus_endpoints: ($explicit_probes + $route_probes),
              victoriametrics_scrape_jobs: $scrape_jobs,
              beszel_agent_listen_port: $beszel_agent_port,
              beszel_systems: $beszel_systems,
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
    | if $backup.enabled then . else
        .pi_appliances.hosts.pi |= with_entries(
          select((.key | startswith("pi_backup_") | not) or .key == "pi_backup_enabled")
        )
      end
  ' >"$output"

jq --exit-status \
  '.pi_appliances.hosts.pi.pi_lan_address as $pi_lan_address
   | .pi_appliances.hosts.pi.pi_routes as $routes
   | .pi_appliances.hosts.pi.ddns_hostnames as $ddns_hostnames
   | .pi_appliances.hosts.pi.authelia_oidc_clients as $oidc_clients
   | .pi_appliances.hosts.pi.gatus_endpoints as $gatus_endpoints
   | .pi_appliances.hosts.pi.victoriametrics_scrape_jobs as $scrape_jobs
   | .pi_appliances.hosts.pi.beszel_systems as $beszel_systems
   | .pi_appliances.hosts.pi.beszel_agent_listen_port as $beszel_agent_port
   | .pi_appliances.hosts.pi.glance_enabled as $glance_enabled
   | .pi_appliances.hosts.pi.glance_bookmark_groups as $glance_bookmark_groups
   | .pi_appliances.hosts.pi.pi_tailnet_workload_ports as $tailnet_workload_ports
   | ([$routes[] | select(.reachability == "internet") | .hostname]) as $expected_ddns_hostnames
   | .pi_appliances.hosts.pi.pi_lan_address != null
   and .pi_appliances.hosts.pi.pihole_lan_address == .pi_appliances.hosts.pi.pi_lan_address
   and .pi_appliances.hosts.pi.pihole_tailnet_address != null
   and (.pi_appliances.hosts.pi.pi_backup_enabled | type == "boolean")
   and (if .pi_appliances.hosts.pi.pi_backup_enabled then
     .pi_appliances.hosts.pi.pi_backup_target_address != null
   and (.pi_appliances.hosts.pi.pi_backup_target_host | type == "string" and test("^[a-z0-9][a-z0-9.-]+$"))
   and (.pi_appliances.hosts.pi.pi_backup_target_user | type == "string" and test("^[a-z_][a-z0-9_-]*$"))
   and .pi_appliances.hosts.pi.pi_backup_repository_prefix == ""
   and (.pi_appliances.hosts.pi.pi_backup_target_known_host | test("^[a-z0-9.-]+ ssh-ed25519 [A-Za-z0-9+/]+={0,3}$"))
   and (.pi_appliances.hosts.pi.pi_backup_jobs | type == "array" and length > 0)
   and (all(.pi_appliances.hosts.pi.pi_backup_jobs[]; (.name | test("^[a-z0-9][a-z0-9-]{0,62}$")) and (.paths | type == "array" and length > 0)))
     else
       (.pi_appliances.hosts.pi | keys | map(select(startswith("pi_backup_")))) == ["pi_backup_enabled"]
     end)
   and (.pi_appliances.hosts | keys == ["pi"])
   and ($beszel_agent_port | type == "number")
   and ($beszel_agent_port > 0)
   and ($beszel_agent_port < 65536)
   and ($beszel_systems | type == "array")
   and ([ $beszel_systems[] | .name ] | unique | length == ($beszel_systems | length))
   and (all($beszel_systems[];
        (.name | type == "string" and test("^[a-z][a-z0-9-]*$"))
        and (.host | type == "string" and length > 0)
        and .port == $beszel_agent_port
      ))
   and ($glance_enabled | type == "boolean")
   and (($glance_enabled == false) or ($glance_bookmark_groups | type == "array" and length > 0))
   and ($tailnet_workload_ports | type == "array")
   and (all($tailnet_workload_ports[]; type == "number" and . > 0 and . < 65536))
   and ($tailnet_workload_ports | unique | length == ($tailnet_workload_ports | length))
   and ([ $glance_bookmark_groups[] | .title ] | unique | length == ($glance_bookmark_groups | length))
   and (all($glance_bookmark_groups[];
        (.title | type == "string" and length > 0)
        and (.links | type == "array" and length > 0)
        and all(.links[];
          (.title | type == "string" and length > 0)
          and (.url | type == "string" and test("^https://[a-z0-9.-]+$"))
          and (.icon | type == "string" and length > 0)
          and (.description | type == "string" and length > 0)
        )
      ))
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
   and ($gatus_endpoints | type == "array" and length >= 5)
   and ([ $gatus_endpoints[] | .name ] | unique | length == ($gatus_endpoints | length))
   and (all($gatus_endpoints[];
        (.name | type == "string" and test("^[a-z][a-z0-9-]*$"))
        and (.url | type == "string" and test("^(https?://[^ ]+|tcp://[^ ]+:[0-9]+)$"))
        and (.interval | type == "string" and length > 0)
        and (.conditions | type == "array" and length > 0)
        and all(.conditions[]; type == "string" and length > 0)
        and ((.headers // {}) | type == "object")
        and all((.headers // {}) | to_entries[];
          (.key | type == "string" and length > 0 and (test("[\\r\\n]") | not))
          and (.value | type == "string" and length > 0 and (test("[\\r\\n]") | not)))
        and ((.client // {}) | type == "object")
        and (.failure_threshold | tonumber > 0)
        and (.send_on_resolved | type == "boolean")
      ))
   and (all(["pihole-dns", "pihole-admin", "station-ssh", "entry-caddy"][];
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
