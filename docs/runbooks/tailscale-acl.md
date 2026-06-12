# Tailscale ACL — snapshot + recovery

The Tailscale ACL (`acls.tailscale.com` JSON config) is the gate for every operator-tier service in the homelab — qBittorrent, *arr stack, ollama, hermes, Grafana, Beszel, VictoriaMetrics, ntfy, all the operator-audience routes. "Tailnet IS the auth perimeter" only holds if the ACL config behind it is correct, current, and recoverable.

Today the ACL lives **only** in the Tailscale admin UI (`login.tailscale.com/admin/acls/file`). Lose admin access or fat-finger the editor and the homelab's auth posture is gone with no second copy.

## What the snapshot is for

A static export committed to `docs/runbooks/tailscale-acl.json`. Two failure modes it covers:

1. **Editor regression** — admin-UI history is shallow. If something breaks and the bad version landed days ago, this file is what to compare against.
2. **Account loss** — if the operator's Tailscale account is locked/lost and a new tailnet is stood up, this file is the seed for the replacement ACL.

It is NOT meant to drive the live ACL — there's no `terraform apply`-equivalent for Tailscale (yet). The admin UI is the source of truth; this snapshot is the recovery backup.

## Cadence

- **After any admin-UI edit** — re-export and commit.
- **Quarterly recheck** — even if nothing's changed.

## Export procedure

Admin UI doesn't expose a download button. Two ways:

### Option A — copy-paste from admin UI

1. Open `https://login.tailscale.com/admin/acls/file`.
2. Select-all in the JSON editor, copy.
3. Overwrite `docs/runbooks/tailscale-acl.json` with the contents.
4. Commit:
   ```sh
   git add docs/runbooks/tailscale-acl.json
   git commit -m "snapshot(tailscale-acl): post-<change> export"
   ```

### Option B — API export

Get an API key from `https://login.tailscale.com/admin/settings/keys` (auth-keys can't read ACL; OAuth client with `policy_file:read` scope can). Then:

```sh
TAILNET="saola-matrix.ts.net"
curl -s -u "${API_KEY}:" \
  -H "Accept: application/hujson" \
  "https://api.tailscale.com/api/v2/tailnet/${TAILNET}/acl" \
  > docs/runbooks/tailscale-acl.json
```

## What's in the ACL today (high-level)

Cross-reference against the JSON to make sure these intents are still encoded:

- **SSH ACL: `action: accept`** for all tag:operator → tag:operator paths (eliminates per-session reauth dance; see [[just-remote-tailnet-hostnames]]).
- **`tag:agent` quarantine** — pavilion's tag, restricted to ollama (workstation:11434) + outbound :443. Verify pavilion CANNOT reach `workstation:9119` (hermes) — that's the load-bearing assumption documented in `home/hermes/default.nix` and NETWORK.md.
- **`tag:family` member tags** — phones + tablets join with this tag; their access scope is the family-tier subset of routes.
- **Per-host subnet/exit-node approvals** — pi is the subnet router + exit node; these need re-approval in admin UI on every key rotation.

## Recovery sequence

```
admin UI access lost
→ Tailscale support: recover account OR provision a new tailnet
→ paste docs/runbooks/tailscale-acl.json content into the new admin UI
→ re-auth every device (machine keys are tailnet-scoped)
→ verify tag:agent quarantine assertion (see above)
→ verify SSH ACL still accepts cross-host operator paths
```

## File format

Tailscale ACL JSON is HuJSON — JSON with comments and trailing commas. Treat the file as HuJSON, not strict JSON. Most editors handle it via the `.jsonc` highlighter.
