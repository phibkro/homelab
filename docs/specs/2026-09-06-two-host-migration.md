# Two-host organization and deferred OneTouch backups

## Outcome

Workstation is the NixOS/Home Manager target; Pi is the Ansible target. Shared
facts live in `inventory/`, workstation realization in `infra/workstation/`,
shared NixOS mechanisms in `infra/common/nixos/`, and Pi assembly and roles in
`infra/pi/` and `services/*/ansible/`. Historical execution documents live in
`docs/archive/`. Aurora and Pavilion leave the main deployment inventory.

```text
inventory/ → infra/workstation/ → workstation
           → infra/pi/ → Pi appliance

SSDs: hot data     IronWolf Pro: cold data
OneTouch: planned backups, disabled pending verified connection
```

The operator selected OneTouch as the backup destination after clarifying the
hot/cold storage policy. If Aurora and its attached OneTouch become reachable,
they may be used as a separately verified temporary backup endpoint. The
September 6 preflight did not establish that reachability.

## Constraints

- Preserve operator-owned edits. Commit `76b9b1a` records the original dirty
  baseline in the isolated migration checkout; the original tree is preserved.
- Preserve existing data, archives and recovery credentials. No formatting,
  archive deletion, live activation or SOPS re-encryption is part of this
  source cleanup.
- Keep backup scheduling disabled until the destination is verified. Retain
  same-disk snapshots and application dumps as local recovery artifacts.
- Preserve operator command entry points and useful backend tests. Nix
  entry-plane tests do not establish production Pi behavior.

## Implementation and evidence

Reuse the existing inventory compiler, inventory-to-Ansible generator,
flake-parts composition, backup modules, Ansible roles and Just commands.
No replacement framework is needed.

| Boundary | Required observation |
|---|---|
| Repository | Original edits preserved; moved paths resolve; generated references agree with source |
| Nix | Workstation builds; applicable checks pass; disabled policy produces no backup jobs or mount |
| Pi | Lint, contracts and syntax pass; disposable convergence exercises enabled transport and safe retirement |
| Data | Existing archives and credentials remain untouched; no physical data migration claimed |
| Later cutover | Connection, identities, capacity, restricted transport, fresh backups and real restores verified |

The [OneTouch runbook](../runbooks/onetouch-backup-cutover.md) owns the later
cutover gates. Until those pass, no current backup coverage is claimed.
