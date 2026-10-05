# Kwyne sealer

This service implements Kwyne Spec 009's authority-host process and Spec 011's
ntfy delivery. Workstation hosts the GitLab authority `kwyne/kwyne` (project 1).
Only the existing sealer project token advances its protected `main`.

## Source and ownership

`src/services/kwyne-sealer/deployment.json` owns the full source commit, control
plane origin/stage, bot identity, repository mappings, polling interval and ntfy
server. The manifest places this outbound-only service on workstation. It has
no listener, ingress route or HTTP health endpoint.

```text
authority main → pinned SHA → root provisioning → read-only Bun bundle
                                                   ↓
SOPS → LoadCredential → kwyne-sealer → control plane / authority / ntfy
```

`kwyne-sealer-source.service` fetches authority `main`, requires the pinned SHA
to be its ancestor, checks the sealed package's exact Bun version, installs with
`bun install --frozen-lockfile --ignore-scripts`, then bundles the real
`src/sealer/main.ts`. The existing authority credential is used only by a Git
fetch command during provisioning: it is not a separate read-only token. No
credential enters a Git URL, argv, bundle or Nix store. Root owns
`/var/lib/kwyne-sealer-source/<SHA>/sealer.js` (0444) and its checksum. The
service user cannot rewrite the code or its parent directories. A successful
bundle is reused only after its checksum passes. No unsealed working checkout
is involved.

Runtime fetching is deliberate: Nix's sandbox cannot authenticate to the
private authority on the host's loopback. This keeps that credential out of
flake URLs, lockfiles and build logs. Provisioning requires GitLab and the npm
registry on its first run for a new SHA; `SealerProvisioningFailure` names the
failed stage and stops startup. There is no unfrozen install or old-code
fallback. Dependency lifecycle scripts do not run as root.

`kwyne-sealer.service` runs as its dedicated user/group, with HOME and private
0700 state at `/var/lib/kwyne-sealer`. The shared filesystem hardening profile
hides `/srv`, `/mnt` and user homes; the unit adds a strict read-only system,
private devices, no capabilities and no core dumps. Only its Git cache and
notification delivery state are writable. Authority refs/receipts reconstruct
the Git cache; notification cursor loss can replay idempotent notifications.
The source bundle is disposable and reconstructed by provisioning.

## Credentials

All keys below are in `secrets/workstation-runtime.yaml`. Values must not be
printed. New runtime keys use root-owned 0400 SOPS files. The shared ntfy
publisher token keeps its existing 0440 mode; the agents topic keeps 0400.
Both keep their existing owner and consumers. Systemd `LoadCredential` creates
private credentials for this unit. The exec wrapper exports them because the
sealed program reads its environment. Root can read that environment; ordinary
users cannot access the dedicated service user's process.

| SOPS key | Consumer |
| --- | --- |
| `gitlab-kwyne-sealer-token` | Existing authority token; source fetch and sealer |
| `kwyne-sealer-access-service-token-id` | Access policy administration; not a client ID |
| `kwyne-sealer-access-client-id` | `CF_ACCESS_CLIENT_ID` |
| `kwyne-sealer-access-client-secret` | `CF_ACCESS_CLIENT_SECRET` |
| `ntfy-publisher-token` | `KWYNE_NTFY_TOKEN`; verified against the Pi SSH stream |
| `ntfy-agents-channel` | Production `KWYNE_NTFY_TOPIC`; existing Pi agents topic |
| `kwyne-j15b-ntfy-topic` | New dedicated J15b topic; never production sealer traffic |

The Access fields were copied with `sops set --value-stdin`, compared exactly
without printing, then `~/.config/kwyne/sealer-access.json` was removed. SOPS is
now their single home. The proposer Access file is unchanged. Gate runs must
read the sealer fields from SOPS, not the removed JSON file. Current source and
Spec 009's running example use `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET`;
the handoff's `KWYNE_SEALER_ACCESS_CLIENT_ID`/`_SECRET` names are not accepted by
the sealed program. Do not substitute them.

SecretSpec scopes `kwyne-sealer` and `kwyne-j15b` expose only their declared
inputs with profile `workstation`. Topic/token changes restart the unit. The
Access service-token UUID remains an encrypted administrative input and is not
loaded by the runtime.

## First activation (lead only)

After reviewing and landing the change, from the canonical homelab checkout:

```bash
just rebuild
sudo systemctl start kwyne-sealer.service
systemctl is-active kwyne-sealer-source.service kwyne-sealer.service
sudo journalctl -u kwyne-sealer-source -u kwyne-sealer --since '-10 minutes' --no-pager
sudo stat -c '%a:%U' /var/lib/kwyne-sealer
sudo systemctl show kwyne-sealer -p User -p Group -p LoadCredential -p MainPID
```

`kwyne-sealer-source` being active means its oneshot completed. `Sealer started`
means configuration/credentials decoded, not that a seal succeeded. Inspect
`Deferred to the next pass` and typed `GitFailure`/`ControlPlaneUnavailable`
messages. Healthy connectivity is demonstrated by successful baseline seeding,
a real seal receipt and acknowledged notification delivery—not just systemd
being active. Do not dump the process environment or credential files.

## Redeploy a newly sealed main

1. Read authority `main` through authenticated Git without printing its token.
   Require a real sealed commit/receipt for every post-bootstrap source update.
2. Update only the full `revision` in `deployment.json` to that authority commit.
   Never set it to an unsealed local commit or a moving branch name.
3. Run `just check`, admitted `just build`, and the VM test below; review/commit.
4. Lead activates the reviewed homelab configuration with `just rebuild`.
   The changed source unit/config restarts provisioning before the main unit.
   If recovering from a failed first provision, use:

```bash
sudo systemctl reset-failed kwyne-sealer-source kwyne-sealer
sudo systemctl restart kwyne-sealer-source
sudo systemctl restart kwyne-sealer
```

The sealer does not automatically upgrade itself when it advances authority
`main`. The explicit homelab pin is the redeployment gate. Rollback selects a
previous reviewed homelab generation/pin; it does not reset authority refs.

## J15b ntfy inputs and permissions

Server: `https://alert.home.phibkro.org`. J15b reads its new dedicated topic
from `kwyne-j15b-ntfy-topic` and its token from `ntfy-publisher-token`.
Production uses the existing `ntfy-agents-channel`. Values remain encrypted.

The existing publisher remains an admin. Its admin grant supplies read/write
access to both topics; ntfy rejects explicit ACL entries for admin users.
No publisher role, credential, or permanent Pi configuration changes are needed.
Anonymous publish and subscribe remain denied. The dedicated topic is available
on first use; ntfy does not require a separate topic-creation API.

An initial explicit-ACL attempt failed because ntfy prohibits admin ACL entries.
The scoped Ansible recovery removed that entry and restored the prior container
configuration. Health returned HTTP 200, anonymous agents subscription returned
403, and one approved authenticated agents test publish returned 200.
The branch contains no ACL or Pi deployment changes. Least-privilege separation
into a regular publisher and explicit topic ACLs is a possible operator follow-up;
it is not part of this change.

## Disposable VM verification

Run serially with other heavy jobs after admission. This runner uses the same
provisioner against the real pinned authority, then injects only its nonsecret
bundle into a disposable VM. The authority credential is removed before Nix
evaluates the VM. The VM uses synthetic 0400 credential files through the real
unit's `LoadCredential`; no production credential or network service is copied.

```bash
nix shell --inputs-from . nixpkgs#bun nixpkgs#git nixpkgs#jq \
  nixpkgs#coreutils nixpkgs#sops -c bash src/services/kwyne-sealer/tests/run.sh
```

The test proves startup of the real sealed sealer, credential delivery at the
exec boundary, private state/root-owned non-writable code, no credential values
in its journal, and typed deferred failures against unreachable loopback Git
and control-plane origins. It does not prove live Worker authentication,
GitLab push authorization, sealing, external ntfy delivery, or host activation.
Those remain lead-run real journeys.
