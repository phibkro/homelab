# Pi failure

**RTO**: <2 hours for full restore. Most tailnet-facing services degrade or break the moment pi goes silent.

## Symptom

`healthchecks.io` fires the off-host alert (pi misses 3+ heartbeats — see `modules/services/heartbeat.nix`). `https://*.home.phibkro.org` either times out (Caddy gone) or resolves to NXDOMAIN (Blocky gone via the Tailscale DNS push). Family-tier services that gate on Authelia OIDC reject every login.

## What still works while pi is down

- **Workstation Blocky secondary** still resolves `*.${nori.domain}` for LAN devices that talk to it directly (`192.168.1.181`). Useful while triaging — point Mac/phone at workstation manually if needed.
- **Backend services on aurora/workstation** are reachable by direct tailnet IP + port (per `nori.lanRoutes.<X>.exposeOnTailnet`). Authelia-gated routes (`family` audience) bypass auth at this layer.
- **Tailscale itself** keeps routing via DERP — pi is the subnet router but tailnet-to-tailnet still works without it.

## Triage

```bash
# From any other tailnet device:
tailscale ping pi                              # is it on the tailnet at all?
ssh nori@pi.saola-matrix.ts.net 'uptime'       # does it answer SSH?
ssh nori@pi.saola-matrix.ts.net 'systemctl --failed --no-pager'
```

If SSH answers but services are down → likely bad config; jump to `bad-config.md`. If SSH dead but `tailscale ping` works → network-stack hung; try a reboot via tailscale ssh / power cycle. If `tailscale ping` fails too → hardware or full network outage.

## Restore options

### Option A — rollback (config-driven outage)

```bash
ssh nori@pi.saola-matrix.ts.net 'sudo nixos-rebuild switch --rollback'
```

Atomic. Same as `bad-config.md`. Verify with `curl -k https://status.home.phibkro.org`.

### Option B — swap to spare SD card / USB SSD (hardware-driven outage)

1. Pull SD card / USB SSD; insert spare provisioned via `nixos-anywhere` from the current flake.
2. Boot pi.
3. Wait for Tailscale to authenticate (the spare carries the existing pi machine key in `/persist/var/lib/tailscale`; if it's a fresh install, run `tailscale up` and approve the new key in the admin UI).
4. Verify entry plane:
   ```bash
   ssh nori@pi.saola-matrix.ts.net 'systemctl status caddy authelia-main blocky'
   curl -k https://status.home.phibkro.org             # gatus → workstation
   curl -k https://auth.home.phibkro.org/api/health    # authelia
   ```

### Option C — temporary tailnet DNS failover (if pi will be down for hours)

Edit Tailscale admin UI → DNS → Global nameservers. Replace pi (`100.100.71.3`) with workstation (`100.81.5.122`). Tailnet devices get DNS within ~60s. **Caddy is still down**, so `*.home.phibkro.org` will resolve to pi's now-dead LAN IP — combine with Option D below or point devices at backend tailnet IPs directly.

### Option D — promote workstation to entry plane (extended outage only)

Last resort. Re-enable Caddy + Authelia on workstation:

1. `nori.lanIp = config.nori.hosts.workstation.lanIp;` in `modules/common/default.nix`.
2. Set `nori.services.caddy.enable = true` and `nori.services.authelia.enable = true` in `machines/workstation/default.nix`.
3. Flip `nori.lanRoutes.auth.runsOn = "workstation"` (override in workstation's config).
4. Open ports 80/443 on workstation's tailnet firewall.
5. `just rebuild` workstation.
6. Tailscale admin UI → DNS push workstation.

Reverse all of the above when pi is back.

## After recovery

1. Verify `restic check` on the OneTouch repos backed up *through* pi — pi's outage may have left a partial snapshot mid-run.
2. Confirm healthchecks.io is green (heartbeat resumed within 60s of pi booting).
3. `git log` to find the trigger if it was config-driven; revert if pushed to `origin/main`.

## What you can rely on

- **The flake is the source of truth.** A fresh pi reinstall via `nixos-anywhere` from the flake reconstitutes Caddy + Authelia + Blocky + heartbeat from zero.
- **Sops secrets persist on `/persist`** (impermanence). A clean boot of the same root drive keeps `restic-password`, `cloudflare_acme_token`, `authelia-*` intact.
- **Wildcard LE cert** is reissued automatically on Caddy start if `/var/lib/caddy` is empty (acme.sh-style state) — DNS-01 against Cloudflare needs only the sops token.

## What this won't recover

- **Authelia session continuity.** All family devices need to log in again. Authelia state (`/var/lib/authelia-main`) is restored from restic if needed, but session cookies don't survive an issuer-key reissue.
- **Blocky's negative cache.** Newly-added `nori.lanRoutes` declarations that landed during the outage need a `blocky.service` restart — see [gotcha-blocky-stale-negative-on-new-lan-route](../../.claude/skills/gotcha-blocky-stale-negative-on-new-lan-route/SKILL.md).
- **Hardware loss of the SD card itself.** Buy a spare; provision it with `nixos-anywhere` from the flake; keep it boxed near the pi.
