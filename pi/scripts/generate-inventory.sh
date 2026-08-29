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
    | ([$inventory.workloads[]?.endpoints? | keys[]] | unique) as $routes
    | {
        _meta: {
          hostvars: {
            pi: {
              ansible_host: $pi_lan_ip,
              ansible_user: $ansible_user,
              pi_lan_address: $pi_lan_ip,
              pi_service_bind_address: $pi_lan_ip,
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
        },
        pi_appliances: {
          hosts: ["pi"]
        }
      }
  ' >"$output"

jq --exit-status \
  '._meta.hostvars.pi.pi_lan_address != null
   and (.pi_appliances.hosts == ["pi"])
   and (._meta.hostvars.pi.pihole_local_dns_records | length > 2)' \
  "$output" >/dev/null

printf '%s\n' "$output"
