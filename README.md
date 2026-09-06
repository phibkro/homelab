# nori homelab

Two deployment targets share one inventory:

```text
inventory/ ──→ infra/workstation: NixOS + Home Manager
           └─→ infra/pi: Ansible appliance

hot data → SSDs       cold data → IronWolf Pro
planned backups → OneTouch (disabled pending connection)
```

Workstation owns the desktop, application services, and attached data disks.
Pi owns the HTTP entry plane, DNS, monitoring, and network appliance services.
Aurora and Pavilion are retired from active configuration. Historical archives
and encrypted secret recipients are handled separately from host removal.

## Start here

| Task | Reference |
|---|---|
| Navigate the repository | [Documentation map](docs/README.md) |
| Understand placement | [Topology](docs/reference/topology.md) |
| Add or change configuration | [Module authoring](docs/reference/module-authoring.md) |
| Build and deploy | [Deployment](docs/reference/deployment.md) |
| Understand backups | [Storage](docs/reference/storage.md) |
| Connect and enable OneTouch backups | [Cutover runbook](docs/runbooks/onetouch-backup-cutover.md) |
| Review the repository reorganization | [Migration spec](docs/specs/2026-09-06-complete-reorganization.md) |

## Common commands

Use `devenv shell` for the repository's pinned tools (`.envrc` selects it
automatically).

```bash
devenv shell -- just --list
devenv shell -- just check
devenv shell -- nix fmt
devenv shell -- just plan-deploy main  # replace with the intended upstream/deployed comparison ref
devenv shell -- just pi::check
devenv shell -- just pi::test
devenv shell -- just pi::plan
```

Activation is a separate operator step: `just rebuild` for workstation and
`just pi::deploy` for Pi. Follow the deployment reference and backup cutover
runbook before activating migration changes.

Shared facts live in `inventory/`; generated catalogs live in
[docs/generated](docs/generated). Nix implementation lives under the paths in
[module authoring](docs/reference/module-authoring.md); Pi implementation lives
in [infra/pi](infra/pi). Keep catalogs derived from inventory rather than copied here.
