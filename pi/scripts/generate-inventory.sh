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
    | ([$inventory.workloads[]?.endpoints? | keys[]] | unique) as $routes
    | [
        {
          name: "pihole",
          hostname: ("pihole." + $inventory.site.domain),
          upstream_address: $pi_lan_ip,
          upstream_port: 8081,
          reachability: "internal"
        }
      ] as $appliance_routes
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
              pi_routes: $appliance_routes,
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
                    $appliance_routes[]
                    | {
                        address: $pi_lan_ip,
                        names: [.hostname]
                      }
                  ]
                + [
                    $routes[] as $route
                    | {
                        address: $pi_lan_ip,
                        names: (
                          [($route + "." + $inventory.site.domain)]
                          + [
                              $inventory.site.deprecatedDomains[]
                              | ($route + "." + .)
                            ]
                        )
                      }
                  ]
              )
            }
          }
        }
      }
  ' >"$output"

jq --exit-status \
  '.pi_appliances.hosts.pi.pi_lan_address != null
   and .pi_appliances.hosts.pi.pihole_lan_address == .pi_appliances.hosts.pi.pi_lan_address
   and .pi_appliances.hosts.pi.pihole_tailnet_address != null
   and (.pi_appliances.hosts | keys == ["pi"])
   and (.pi_appliances.hosts.pi.pi_routes | length == 1)
   and (.pi_appliances.hosts.pi.pi_routes[0].hostname
        == ("pihole." + .pi_appliances.hosts.pi.pi_domain))
   and (.pi_appliances.hosts.pi.pihole_local_dns_records | length > 2)' \
  "$output" >/dev/null

printf '%s\n' "$output"
