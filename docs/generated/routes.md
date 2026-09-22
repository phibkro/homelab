---
generated: true
source: flake.nix § packages.docs-routes
regenerate: nix build .#docs-routes
---

# Active HTTP routes

This table is generated from `lib.noriInventory.routes`. Workload
manifests own endpoint declarations. The inventory compiler resolves
placement and policy before NixOS and Ansible adapters consume them.

| Route | Workload | Host | Port | Reachability | Audience | Authentication | Monitor | Public status |
|---|---|---:|---:|---|---|---|:---:|:---:|
| `ai` | `ollama` | `workstation` | `11434` | `internal` | `operator` | `none` | yes | no |
| `alert` | `ntfy-server` | `pi` | `8091` | `internal` | `operator` | `none` | yes | no |
| `audio` | `navidrome` | `workstation` | `4533` | `internet` | `family` | `none` | yes | yes |
| `auth` | `authelia` | `pi` | `9091` | `internal` | `public` | `none` | yes | no |
| `books` | `calibre-web` | `workstation` | `8084` | `internal` | `family` | `forward-auth` | yes | no |
| `cache` | `attic` | `adelie` | `5000` | `internal` | `operator` | `none` | yes | no |
| `calendar` | `radicale` | `adelie` | `5232` | `internal` | `family` | `none` | yes | no |
| `chatlog` | `chatlog` | `workstation` | `4790` | `internal` | `operator` | `none` | yes | no |
| `comics` | `komga` | `workstation` | `8085` | `internal` | `family` | `forward-auth` | yes | no |
| `downloads` | `qbittorrent` | `workstation` | `8083` | `internal` | `operator` | `forward-auth` | yes | no |
| `home` | `glance` | `pi` | `8086` | `internal` | `public` | `none` | yes | no |
| `indexers` | `prowlarr` | `workstation` | `9696` | `internal` | `operator` | `none` | yes | no |
| `logs` | `victorialogs-server` | `pi` | `9428` | `internal` | `operator` | `none` | yes | no |
| `manga` | `suwayomi` | `workstation` | `8088` | `internal` | `family` | `forward-auth` | yes | no |
| `media` | `jellyfin` | `workstation` | `8096` | `internet` | `family` | `none` | yes | yes |
| `memory-origin` | `hindsight` | `workstation` | `9078` | `internal` | `operator` | `none` | no | no |
| `metrics` | `beszel-hub` | `pi` | `8090` | `internal` | `operator` | `oidc` | yes | no |
| `movies` | `radarr` | `workstation` | `7878` | `internal` | `operator` | `none` | yes | no |
| `music` | `lidarr` | `workstation` | `8686` | `internal` | `operator` | `none` | yes | no |
| `news` | `miniflux` | `adelie` | `8087` | `internal` | `family` | `oidc` | yes | no |
| `ops` | `grafana` | `adelie` | `3000` | `internal` | `operator` | `none` | yes | no |
| `papers` | `paperless` | `workstation` | `28981` | `internal` | `operator` | `none` | yes | no |
| `photos` | `immich` | `workstation` | `2283` | `internal` | `family` | `oidc` | yes | no |
| `pihole` | `pihole` | `pi` | `8081` | `internal` | `operator` | `none` | yes | no |
| `projects-origin` | `herdr-projects-mcp` | `workstation` | `9081` | `internal` | `operator` | `none` | no | no |
| `requests` | `jellyseerr` | `workstation` | `5055` | `internet` | `family` | `none` | yes | yes |
| `status` | `gatus` | `pi` | `8089` | `internet` | `public` | `none` | no | no |
| `stremio` | `stremio` | `adelie` | `11470` | `internal` | `operator` | `none` | yes | no |
| `subtitles` | `bazarr` | `workstation` | `6767` | `internal` | `operator` | `none` | yes | no |
| `sync` | `syncthing` | `workstation` | `8384` | `internal` | `operator` | `none` | yes | no |
| `tsdb` | `victoriametrics` | `pi` | `8428` | `internal` | `operator` | `none` | yes | no |
| `tv` | `sonarr` | `workstation` | `8989` | `internal` | `operator` | `none` | yes | no |
| `uptime` | `gatus` | `pi` | `8082` | `internal` | `operator` | `none` | no | no |
| `vault` | `vaultwarden` | `adelie` | `8222` | `internal` | `family` | `oidc` | yes | no |
