# Pi changes

Start with [the shared guide](../../AGENTS.md) and [deployment guide](../../docs/reference/deployment.md). Run recipes
from the repository root as `just pi::<recipe>` so the pinned Pi toolchain is used.

Shared host identity, placement, endpoints and backup policy come from
`inventory/`; the Pi generator translates public inventory into Ansible input.
The generator is `infra/pi/scripts/generate-inventory.sh`; `infra/pi/playbooks/pi.yml`
selects roles. Edit the canonical declaration or generator, never its generated
output. Roles own the appliance implementation. Read the role defaults, tasks, templates
and callers together before changing their contract.

- `just pi::check`: lint, syntax and generator/role contract checks.
- `just pi::test`: real disposable ARM guest convergence, repeat convergence,
  recovery and reboot checks. It is a heavy job; coordinate ownership.
- `just pi::plan`: production connection and Ansible check mode. It requires
  production credentials and an authenticated host; it is not an offline test.
- `just pi::deploy` and `just pi::enroll`: live effects requiring applicable
  operator authorization and the production runner's target confirmation.

Keep SecretSpec inputs and SSH verification in the existing production runner.
A host-key mismatch requires independent identity verification, never a trust
reset. Test backup enable/disable transitions and preservation of existing state;
a declared destination is not evidence that a disk is mounted or recoverable.

VM tests create a unique owned directory under `.artifacts/pi-vm/` and print its
path. Each attempt retains logs and `result.json` with revision, source hashes,
phase and outcome. Reuse requires both `PI_VM_STATE_DIR=<printed-path>` and
`PI_VM_REUSE=true`; existing unowned directories are rejected. The runner holds a
user-wide lock for its fixed ports. With `PI_VM_KEEP_ON_FAILURE=true`, a failed
guest retains that lock until the guest stops; the result records its PID and
guardian. Preserve evidence and stop that exact guest before removing owned state.
