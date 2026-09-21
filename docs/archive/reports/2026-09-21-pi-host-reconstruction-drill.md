# Pi host reconstruction drill — September 21, 2026

This drill proved a complete disposable reconstruction journey for the Pi
appliance. It built a clean ARM64 guest, converged the real Ansible playbook,
restored state, rebooted, and served recovered Pi-hole data.

The run used base revision `124218604bdd026546430d26702927452ab40775`.
The passing clean-guest run recorded working-state hash
`a9edc76f80f1fc0683c33d3d1052328c3282d9f75f4bf81a931b8342727b52dd`.

## Scope

The standard `just pi::test` harness created a new 16 GiB qcow2 overlay from
the cached Debian 12 ARM64 cloud image. It did not use `PI_VM_REUSE`.

QEMU used ARM64 TCG, four virtual CPUs, 3 GiB of memory, and user-mode
networking. All host forwarding bound to loopback. The guest used generated
test credentials and an in-guest SFTP receiver. It did not receive production
credentials or write to OneTouch.

The harness then:

1. waited for cloud-init and SSH;
2. converged `infra/pi/playbooks/pi.yml` twice;
3. required a zero-change second convergence;
4. created and restored an in-guest Restic fixture;
5. compared the restored Pi-hole file with its source;
6. rejected an SFTP escape outside the repository namespace;
7. checked blocked and allowed DNS results;
8. checked Caddy HTTP-to-HTTPS and Pi-hole routing;
9. removed scheduled backup units while preserving recovery data;
10. required a zero-change second removal convergence;
11. rebooted the guest and repeated DNS, HTTPS, and backup-retirement checks.

After that run passed, the retained reconstructed guest booted again. The
current production Pi-hole snapshot was restored to scratch on the Pi. Only
its Pi-hole data was copied into the guest. The guest Pi-hole container was
stopped before its volume was replaced, then restarted before verification.

## Failure found and fixed

The first clean run reached Pi-hole before its new `gravity.db` contained the
`adlist` table. Adlist reconciliation failed with:

```text
no such table: adlist
```

The Pi-hole role now waits for a non-empty gravity database and the `adlist`
schema before it reconciles adlists. This is an application-readiness gate;
a running container alone is not sufficient.

The failed attempt is retained at:

```text
.artifacts/pi-vm/run.qctOS6Tw/attempt.IPm0shyH/result.json
```

It records `outcome: failed` and phase `enabled-first-convergence`.

## Clean-host result

The corrected `devenv shell -- just pi::test` run completed in 2,943.42
seconds.

| Check | Result |
|---|---|
| Result | `passed` |
| Final phase | `complete` |
| Source state changed during run | no |
| First convergence | passed |
| Second convergence | zero changes |
| Fixture restore | byte-identical |
| SFTP namespace escape | rejected |
| DNS filtering before reboot | passed |
| HTTPS routing before reboot | passed |
| Backup retirement | preserved recovery data |
| Reboot | passed |
| DNS and HTTPS after reboot | passed |

The retained result and non-secret logs are at:

```text
.artifacts/pi-vm/run.3fHkS3xY/attempt.p7jtCFrH/
```

The role needed one readiness retry on the clean guest. The gravity database
became usable before the next retry completed.

## Current-state restore result

The production restore helper selected Pi-hole snapshot `08b0962c`, created at
2026-09-21 03:17:03 CEST. It restored 42 files and directories, totaling
86.964 MiB, into a scratch directory.

The local restored files and the guest files had equal hashes:

| File | SHA-256 |
|---|---|
| `gravity.db` | `46aad30a8a77915065d31801794a051c3d38e253565f8a05de716f766fd531e6` |
| `05-homelab-local-records.conf` | `4c0710e4e0011e7bf62616a2921097d5391e3c6fac908a9bf19e8a312aa706de` |

The reconstructed guest then returned:

| Check | Result |
|---|---|
| `PRAGMA integrity_check` | `ok` |
| Enabled adlists | 1 |
| Gravity domains | 76,230 |
| `workstation.home.phibkro.org` | `192.168.1.181` |
| `doubleclick.net` | `0.0.0.0` |
| Pi-hole through reconstructed Caddy HTTPS | HTTP `302` from `/admin/` |

This connects current off-host state to an application endpoint on the same
clean guest that passed configuration convergence and reboot checks.

## Cleanup and production check

The QEMU process stopped cleanly. The remote restore directory and local
transfer directory were removed. The qcow2 overlay was also removed because it
contained copied production state. The result and text logs remain.

No production service or volume was stopped or changed. After cleanup, the
production Pi still returned `192.168.1.181` for the workstation record and
`0.0.0.0` for `doubleclick.net`.

## Evidence boundary

This closes the software-side disposable host reconstruction proof for one
representative stateful service. It establishes this chain:

```text
clean Debian guest
  -> current Ansible configuration
  -> idempotent convergence
  -> backup and restore mechanics
  -> reboot
  -> current Pi-hole snapshot
  -> restored DNS and HTTPS behavior
```

It does not establish:

- flashing or replacing the physical boot medium;
- production SecretSpec recovery;
- Tailscale node identity recovery;
- public DNS, ACME, router, or off-LAN behavior;
- restored state for every Pi service;
- a measured physical-Pi recovery time.

A physical replacement remains an operator-gated hardware exercise. Do not
copy the live Tailscale identity to a second node. Use the Pi failure runbook
for an actual incident.
