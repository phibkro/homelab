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
    | $inventory.hosts.pi.lanIp as $pi_lan_ip
    | $inventory.hosts.pi.tailnetIp as $pi_tailnet_ip
    |
      [
        $inventory.workloads
        | to_entries[]
        | select(.value.active != false)
        | .value.endpoints // {}
        | to_entries[]
        | . as $endpoint
        | $inventory.hosts[$endpoint.value.runsOn] as $backend_host
        | {
            name: $endpoint.key,
            hostname: ($endpoint.key + "." + $inventory.site.domain),
            upstream_address: (
              if $endpoint.value.runsOn == $inventory.site.entryPlaneHost
              then $pi_lan_ip
              else $backend_host.tailnetIp
              end
            ),
            upstream_port: $endpoint.value.port,
            scheme: ($endpoint.value.scheme // "http"),
            reachability: ($endpoint.value.reachability // "internal"),
            audience: ($endpoint.value.audience // "operator"),
            auth: (
              if $endpoint.value.forwardAuth != null then "forward-auth"
              elif $endpoint.value.oidc != null then "oidc"
              else "none"
              end
            ),
            forward_auth_exempt_paths: (
              $endpoint.value.forwardAuth.exemptPaths // []
            ),
            forward_auth_upstream: ($pi_lan_ip + ":9091"),
            oidc_redirect_path: ($endpoint.value.oidc.redirectPath // null),
            upstream_host_header: ($endpoint.value.upstreamHostHeader // null),
            upstream_origin_header: ($endpoint.value.upstreamOriginHeader // null)
          }
      ]
      | sort_by(.name) as $service_routes
    | (
      [
        {
          name: "pihole",
          hostname: ("pihole." + $inventory.site.domain),
          upstream_address: $pi_lan_ip,
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
      ] + $service_routes) as $appliance_routes
    | {
        pi_appliances: {
          hosts: {
            pi: {
              ansible_host: $pi_lan_ip,
              ansible_user: $ansible_user,
              pi_lan_address: $pi_lan_ip,
              pi_service_bind_address: $pi_lan_ip,
              pihole_lan_address: $pi_lan_ip,
              pihole_tailnet_address: $pi_tailnet_ip,
              pi_domain: $inventory.site.domain,
              pi_deprecated_domains: $inventory.site.deprecatedDomains,
              pi_routes: $appliance_routes,
              # Cloudflare DDNS owns only explicitly internet-reachable
              # route hostnames; host vars override the group fallback.
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
                      names: [(.key + "." + $inventory.site.domain)]
                    }
                ]
                + [
                    $appliance_routes[] as $route
                    | {
                        address: $pi_lan_ip,
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
   | ([$routes[] | select(.reachability == "internet") | .hostname]) as $expected_ddns_hostnames
   | .pi_appliances.hosts.pi.pi_lan_address != null
   and .pi_appliances.hosts.pi.pihole_lan_address == .pi_appliances.hosts.pi.pi_lan_address
   and .pi_appliances.hosts.pi.pihole_tailnet_address != null
   and (.pi_appliances.hosts | keys == ["pi"])
   and (.pi_appliances.hosts.pi.pi_routes | length > 1)
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
   and ([ $routes[] | (.upstream_address + ":" + (.upstream_port | tostring)) ]
        | unique | length == ($routes | length))
   and ($ddns_hostnames == $expected_ddns_hostnames)
   and ([.pi_appliances.hosts.pi.pihole_local_dns_records[] | .names[]]
        | length == (unique | length))' \
  "$output" >/dev/null

printf '%s\n' "$output"
