# GitLab authority plane

GitLab CE is the canonical Git store of the Kwyne authority plane. Kwyne
ADR-0006 and Spec 009 (in the `kwyne` repository) define the contract: the Kwyne
sealer is the only identity that moves `main` or creates a `kwyne/seal/*` tag.
This runbook activates the service, applies the protections that GitLab keeps
in its database, and operates it afterwards.

The service is declared in `src/services/gitlab/`. Backup and secret facts come
from the evaluated host configuration. The VM check `e2e-gitlab` runs the Git
and API calls of [First-time setup](#first-time-setup) and the restore of
[Restore](#restore) against the configured GitLab package, and shows the refusal messages quoted
here.

## Placement

| Fact | Value |
| --- | --- |
| Host | `workstation` |
| Listener | `100.81.5.122:8929` |
| Secrets file | `secrets/workstation-runtime.yaml` |
| Activation | `just rebuild` (run on the workstation) |
| Backup transport | Local Restic repository `/mnt/backup/gitlab` on the OneTouch disk, which is attached to the same host |
| Intended home | `adelie`. See [Fallback on workstation](#fallback-on-workstation) |

The manifest `src/services/gitlab/manifest.nix` owns the placement. The check
`eval-gitlab-authority` fails when the Host, Listener or Secrets file row differs
from the manifest, the tailnet address of that host, or the secrets file.

In the commands below, set `HOST` to the Host row:

```bash
HOST=workstation
```

Run the commands that name `systemctl`, `journalctl`, `sudo` or `127.0.0.1` on
that host (`ssh nori@$HOST.saola-matrix.ts.net` from another machine).

### Fallback on workstation

GitLab runs on `workstation` because `adelie` is offline, and the operator
authorized that placement on 2026-10-04. Adelie stays the intended home: it has
no agent fleet and no media load, and the OneTouch disk is attached to another
machine, so the backup survives the loss of the GitLab host. The fallback
differs in these ways:

- **Memory.** GitLab shares 64 GB with the desktop session, the media services
  and the agent fleet. The incident in
  [the 2026-07-20 oomd report](../archive/reports/2026-07-20-oomd-agent-fleet-kill.md)
  came from that load. Nothing caps `system-gitlab.slice`. Read per-process RSS
  from process-exporter after a week, then decide on a `MemoryHigh` value.
- **Backup domain.** The live data, the daily btrbk snapshots of `/var/lib`, the
  IronWolf copy of those snapshots and the OneTouch Restic repository are all
  attached to one machine. The OneTouch repository survives the failure or the
  corruption of one disk, and an accidental deletion. It does not survive the
  loss of the workstation itself. No off-site copy of GitLab exists. The Kwyne
  sealer replicates `main` to the Cloudflare baseline, but not the seal tags.
- **PostgreSQL.** GitLab uses the shared instance of the workstation. The first
  activation sets `max_locks_per_transaction`, so PostgreSQL restarts once. That
  interrupts Immich and Paperless for a few seconds. The cloudflared tunnel also
  forwards `vektor-db-origin.phibkro.org` to this instance (`tcp://127.0.0.1:5432`).
  The `gitlab` role has no password, so a password login over TCP cannot
  succeed. Only the socket login (peer) works. No `pg_hba.conf` rule rejects the
  `gitlab` database by name. Add one if that tunnel route stays.
- **Secrets.** The GitLab keys live in `secrets/workstation-runtime.yaml`.

## Exposure

| Surface | Address | Boundary |
| --- | --- | --- |
| HTTP (Caddy `gitlab-proxy`) | `127.0.0.1:8929` | Host only |
| HTTP (Caddy `gitlab-proxy`) | The Listener row of the placement table | Tailnet only. The firewall opens port 8929 on `tailscale0` and nowhere else. The tailnet ACL decides which tailnet nodes connect |
| Workhorse, Puma, Gitaly | Unix sockets in `/run/gitlab` and `/var/lib/gitlab/tmp/sockets` | Host only. The Workhorse socket accepts any local account |
| Metrics exporters | `localhost:9236` (Gitaly), `localhost:3807` (Sidekiq) | Host only |
| PostgreSQL (shared instance, database `gitlab`) | Unix socket and `localhost:5432` | Host only |
| Redis | `/run/gitlab/redis.sock`. TCP is off | Host only |
| Git over SSH | Off | `sshd` denies the `gitlab` account. Step 2 also limits Git to HTTP(S) |

The browser URL is `http://$HOST.saola-matrix.ts.net:8929`. Plain HTTP is
acceptable here, because every path stays on loopback or on the encrypted
tailnet.

GitLab has no `endpoints` in its manifest. It therefore has no Pi Caddy route, no
Pi-hole record and no Gatus probe. The workstation tunnel `mcp-origin-cloudflared`
lists its ingress by hand in `src/services/mcp-origin-tunnel/nixos.nix`. The check
`eval-gitlab-authority` fails if an endpoint, a route or a mention of GitLab or of
its port appears there. `e2e-gitlab` fails if any other TCP listener accepts
connections outside loopback.

The monitoring endpoints (`/-/readiness`, `/-/health`, `/-/liveness`,
`/-/metrics`) answer only to client addresses on the GitLab allowlist, or to a
request that carries the health check access token, which only an administrator
can read. The NixOS module allows loopback only. `e2e-gitlab` shows that the
same requests through the tailnet listener get 404, so run the probes on the
GitLab host
([IP allowlist](https://docs.gitlab.com/19.3/administration/monitoring/ip_allowlist/)).

## Secrets

All values live in the Secrets file of the placement table. Activation installs
the service keys for `gitlab` with mode `0400`. The operational password and
sealer token stay encrypted in SOPS; no service consumes them yet. The age key
of that host decrypts the service keys at activation. The operator keys listed
for the file in `.sops.yaml` can decrypt it too. No other host can.
`secretspec.toml` lists the service keys in the profile of that host.

| SOPS key | Use | Change it |
| --- | --- | --- |
| `gitlab-initial-root-password` | Password of `root`. GitLab reads it only when it creates the first administrator | A later change in the file does not change the live password. Step 1 replaces the live password at once |
| `gitlab-root-password` | Current operational password of `root` | Change the live password and this encrypted value together |
| `gitlab-kwyne-sealer-token` | Project access token for the Kwyne sealer | Rotate before expiry; replace this encrypted value |
| `gitlab-secret-key-base` | Rails `secret_key_base` | Never on an instance with data |
| `gitlab-otp-key-base` | Rails `otp_key_base` | Never on an instance with data |
| `gitlab-db-key-base` | Rails `db_key_base` | Never on an instance with data |
| `gitlab-openid-connect-signing-key` | RSA key for OpenID Connect tokens | Never on an instance with data |
| `gitlab-active-record-encryption-primary-key` | Encrypts database columns | Never on an instance with data |
| `gitlab-active-record-encryption-deterministic-key` | Encrypts database columns | Never on an instance with data |
| `gitlab-active-record-encryption-key-derivation-salt` | Derives the column encryption keys | Never on an instance with data |

A restore needs the same values, because the backup archive does not contain
them ([backup guide](https://docs.gitlab.com/19.3/administration/backup_restore/backup_gitlab/)).
They were generated once with `openssl rand -hex 64` (key bases),
`openssl rand -hex 32` (Active Record), `openssl genrsa 2048` (OpenID Connect)
and `openssl rand -hex 20` (root password), and stored with
`sops set --value-stdin`. Do not print them. When GitLab moves to another host,
move the same values to that host's secrets file.

If a Rails key leaks, it cannot rotate in place. Treat the instance as
compromised, rebuild it from the repositories, and issue new tokens.

## Activation

Activation is an operator action. Do not run it from an agent session.

1. Read the plan. It must select only the host of the placement table:

   ```bash
   nix run .#deployment-plan -- --workload gitlab
   ```

2. Build and check the revision that you will activate:

   ```bash
   just check
   nix build ".#nixosConfigurations.$HOST.config.system.build.toplevel"
   just check-vm e2e-gitlab
   ```

3. Run the Activation command of the placement table.

The first activation changes the host in these ways:

- It creates the `gitlab` user, `/var/lib/gitlab` and a Redis instance on a Unix socket.
- It adds the `gitlab` database and role to the shared PostgreSQL 17 instance.
- It sets `max_locks_per_transaction` to 128 for that instance. PostgreSQL restarts once, and every service that is bound to it restarts with it. On `adelie` that is Miniflux. On `workstation` it is Immich, Paperless and their helpers.
- It opens port 8929 on `tailscale0` and starts `gitlab-proxy`.
- It runs the database migrations on the first start. Allow several minutes.

After the first start, verify on the GitLab host:

```bash
systemctl is-active gitlab.target gitlab-proxy.service
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8929/-/readiness
```

Both units must report `active`, and the readiness probe must print `200`
([health checks](https://docs.gitlab.com/19.3/administration/monitoring/health_check/)).
From another tailnet host, this command must also print `200`:

```bash
curl -s -o /dev/null -w '%{http_code}\n' "http://$HOST.saola-matrix.ts.net:8929/users/sign_in"
```

Until step 2 closes sign-ups, any tailnet client can register an account that
waits for approval. Do steps 1 and 2 in one sitting.

## First-time setup

Run these steps once, after the first activation. GitLab stores the results in
its database. They are part of the restic backup and of a restore.

### Workstation setup record (2026-10-04)

The password replacement, settings, project, protections, and sealer token are
complete. Runbook steps 1–6 are complete. The operator registered a root
one-time-password authenticator on 2026-10-04. No temporary administrator token was necessary.

| Fact | Observed value |
| --- | --- |
| Group | `kwyne` (id `2`), private; `root` is its Owner |
| Project | `kwyne/kwyne` (id `1`), private, empty; no README or seed commit |
| Project URL | `http://workstation.saola-matrix.ts.net:8929/kwyne/kwyne` |
| Sign-ups / Git protocol | `signup_enabled=false`; `enabled_git_access_protocol=http` |
| Initial branch protection | Fully protected (`2`); push/merge `40`, force push off, Developer initial push off |
| `main` rule | Push and merge: Maintainers (`40`); force push off |
| Tag rules | `kwyne/seal/*`, `kwyne`, and `kwyne/seal`; create: Maintainers (`40`) |
| Token | `kwyne-sealer`, id `1`, Maintainer (`40`), scope `write_repository` only |
| Token expiry | `2027-04-02` at midnight UTC (180 days after creation) |
| Maintainer | `project_1_bot_fac313f36031805513c69779e8067a27` (the sealer bot) |
| Owner | `root`, inherited from `kwyne`; no shared groups or other writers |
| Root email | `philib.krogh@gmail.com`, confirmed with `gitlab-rails` (no SMTP) |
| Added SOPS keys | `gitlab-root-password`, `gitlab-kwyne-sealer-token` |

Real Git over loopback HTTP proved these boundaries in disposable scratch clones:

- The sealer atomic push created `main` and `kwyne/seal/test-0`: `[new branch]` and `[new tag]`.
- A non-fast-forward force push failed: `GitLab: You are not allowed to force push code to a protected branch on this project.`
- `GET /api/v4/projects/1` with the sealer token returned HTTP 403, `insufficient_scope`.
- A push without credentials failed: `could not read Username ... terminal prompts disabled`. The receive-pack discovery returned HTTP 401.

The administrator then removed the test branch and tag through `gitlab-rails`
as `gitlab`: unprotect, Gitaly `delete_refs`, expire repository caches, and reprotect.
Direct administrative ref deletion avoids the default-branch deletion guard.
Readback showed an empty repository, no branches, no tags, and all protections restored.
The project and token were not recreated. Temporary credential files, helpers,
and scratch clones were deleted. The seeded root-password key stayed unchanged.
No NixOS rebuild or activation was necessary.

Each step gives the UI path. Steps 2 to 6 also give the API call. `e2e-gitlab` runs
the API calls of steps 2 to 6 and the refusals of step 8. It does not cover the
sign-in of step 1 and the member check of step 7. Use the UI if you do not want an
API token.

### 1. Sign in as root and replace the password

The initial password sits in `gitlab-initial-root-password`. GitLab reads it
only during database creation. Keep that seeded key unchanged after setup.
The current workstation password now sits in `gitlab-root-password`.

Copy the current password to your clipboard. Do not print it or paste it into a log or a chat:

```bash
sops decrypt --extract '["gitlab-root-password"]' secrets/workstation-runtime.yaml | wl-copy
```

1. Open `http://$HOST.saola-matrix.ts.net:8929` and sign in as `root`.
2. Select your avatar, then **Edit profile** > **Access** > **Password and authentication**.
3. Register your authenticator under **One-time password authenticator** ([two-factor authentication](https://docs.gitlab.com/19.3/user/profile/account/two_factor_authentication/)).

The password replacement and the authenticator registration are complete.
If you change the password, update the current SOPS key through
`sops set --value-stdin`; do not change the seeded key.

GitLab has no SMTP configuration, so it cannot send confirmation mail. After you
change an email address in **Edit profile** > **Emails**, confirm it on the host:

```bash
sudo -n -u gitlab gitlab-rails runner 'u = User.find_by_username("root"); u.confirm; puts u.reload.email'
```

`services.gitlab.initialRootEmail` only seeds a new database; keep it equal to
the live address so a restore onto an empty host starts with the same identity.

If you lose the password, reset it on the GitLab host
([reset a user password](https://docs.gitlab.com/19.3/security/reset_user_password/)):

```bash
sudo -u gitlab gitlab-rake gitlab:password:reset
```

### API token (optional)

The API calls of steps 2 to 6 need a short-lived token. Create a personal access
token for `root` with the `api` scope and an expiry of one day
([create a personal access token](https://docs.gitlab.com/19.3/user/profile/personal_access_tokens/#create-a-personal-access-token)).
Revoke it when step 6 is done. The function below gives the token to `curl`
through a config file, so it does not appear in the process list.

```bash
GITLAB=http://$HOST.saola-matrix.ts.net:8929
read -rs ADMIN_PAT        # paste the token, then press Enter
api() { curl -sS --fail-with-body -K <(printf 'header = "Authorization: Bearer %s"\n' "$ADMIN_PAT") -H 'Content-Type: application/json' "$@"; }
```

### 2. Close sign-ups and limit Git to HTTP(S)

UI:

1. Select **Admin**, then **Settings** > **General**.
2. Expand **New user account restrictions**. Clear **Allow new user accounts**. Select **Save changes**.
3. Expand **Visibility and access controls**. Set **Enabled Git access protocols** to **Only HTTP(S)**. Select **Save changes**.

API:

```bash
api -X PUT "$GITLAB/api/v4/application/settings" \
  -d '{"signup_enabled":false,"enabled_git_access_protocol":"http"}'
```

Then check one more setting in the UI. In the Admin area, select **Settings** >
**Repository**, expand **Default branch**, and check that **Initial default branch
protection** is **Fully protected**. That is the default. GitLab applies it to the
first push into an empty repository before it applies the rule of step 4.

Sources: [new user account restrictions](https://docs.gitlab.com/19.3/administration/settings/sign_up_restrictions/#disable-new-user-account-creation),
[enabled Git access protocols](https://docs.gitlab.com/19.3/administration/settings/visibility_and_access_controls/#configure-enabled-git-access-protocols),
[settings API](https://docs.gitlab.com/19.3/api/settings/),
[initial default branch protection](https://docs.gitlab.com/19.3/user/project/repository/branches/default/).
The GitLab setting applies inside the application. The `sshd` rule `DenyUsers gitlab`
blocks the transport.

### 3. Create the project

Create an empty private project. Do not add a README. The sealer pushes the
first commit.

1. Select **Create new** > **New project/repository** > **Create blank project**.
2. Enter the project name and choose the namespace.
3. Set **Visibility Level** to **Private**. Clear **Initialize repository with a README**.

Source: [create a blank project](https://docs.gitlab.com/19.3/user/project/).

Create the private `kwyne` group first. Keep its response id as `GROUP_ID`.
Then create the empty project in that namespace:

```bash
api -X POST "$GITLAB/api/v4/groups" \
  -d '{"name":"Kwyne","path":"kwyne","visibility":"private"}'
# Set GROUP_ID from the response; the workstation group id is 2.
api -X POST "$GITLAB/api/v4/projects" \
  -d "{\"name\":\"Kwyne\",\"path\":\"kwyne\",\"namespace_id\":$GROUP_ID,\"visibility\":\"private\",\"initialize_with_readme\":false}"
```

Keep the project response id as `PROJECT_ID`, and set `PROJECT=kwyne/kwyne`.

### 4. Protect `main`

Only the Maintainer role or a higher role can push or merge. Nobody can force push.

UI: **Settings** > **Repository** > **Branch rules** > **Add branch rule** >
**Branch name or pattern**. Select `main` and select **Create branch rule**.
Set **Allowed to merge** and **Allowed to push and merge** to **Maintainers**.
Keep force push off. The project is empty at this point. Use the API call below
there: `e2e-gitlab` runs it on an empty repository and gets HTTP 201. The UI
path on an empty repository is not verified.

```bash
api -X POST "$GITLAB/api/v4/projects/$PROJECT_ID/protected_branches" \
  -d '{"name":"main","push_access_level":40,"merge_access_level":40,"allow_force_push":false}'
```

Sources: [protected branches](https://docs.gitlab.com/19.3/user/project/repository/branches/protected/),
[protected branches API](https://docs.gitlab.com/19.3/api/protected_branches/).
Set both access levels explicitly. The API default is Maintainer, but the UI
default is "No one".

### 5. Protect the seal tags

Only the Maintainer role can create a tag that matches `kwyne/seal/*`. GitLab
also refuses to update such a tag, and refuses to delete it through Git.

UI: **Settings** > **Repository** > **Protected tags** > **Add new**. Select
**Tag**, enter `kwyne/seal/*`, and select **Create wildcard**. Set **Allowed to
create** to **Maintainers**. Select **Protect**.

```bash
api -X POST "$GITLAB/api/v4/projects/$PROJECT_ID/protected_tags" \
  -d '{"name":"kwyne/seal/*","create_access_level":40}'
api -X POST "$GITLAB/api/v4/projects/$PROJECT_ID/protected_tags" \
  -d '{"name":"kwyne","create_access_level":40}'
api -X POST "$GITLAB/api/v4/projects/$PROJECT_ID/protected_tags" \
  -d '{"name":"kwyne/seal","create_access_level":40}'
```

The exact `kwyne` and `kwyne/seal` rules close the tag-prefix gap. Such tags
can block later refs below them. The VM check verifies all three rules together.

Sources: [protected tags](https://docs.gitlab.com/19.3/user/project/protected_tags/),
[protected tags API](https://docs.gitlab.com/19.3/api/protected_tags/).

### 6. Issue the sealer token

The sealer authenticates with a project access token. It has the Maintainer
role, which the rules in steps 4 and 5 require, and the single scope
`write_repository`.

UI: **Settings** > **Access tokens** > **Add new token**. Enter the name
`kwyne-sealer`, an expiry date within 365 days, the role **Maintainer**, and the
scope **write_repository**. Select **Create project access token** and save the
token. GitLab shows it once.

```bash
( umask 077
  api -X POST "$GITLAB/api/v4/projects/$PROJECT_ID/access_tokens" \
    -d "{\"name\":\"kwyne-sealer\",\"scopes\":[\"write_repository\"],\"access_level\":40,\"expires_at\":\"$(date -d '+180 days' +%F)\"}" \
    > sealer-token.json )
jq '{id, name, access_level, scopes, expires_at}' sealer-token.json
```

The printed `id` is the token id. Keep it for the rotation below. The file
`sealer-token.json` holds the only copy of the `token` field. Move that field into
the secret store of the sealer and delete the file. Sources:
[project access tokens](https://docs.gitlab.com/19.3/user/project/settings/project_access_tokens/),
[project access tokens API](https://docs.gitlab.com/19.3/api/project_access_tokens/),
[token scopes](https://docs.gitlab.com/19.3/security/tokens/access_token_scopes/).

Why this is the minimum:

- `write_repository` grants Git read and push over HTTP. It does not authenticate the REST API (GitLab answers 403 `insufficient_scope`). A sealer token cannot change a protection rule.
- The token belongs to one project. A group token reaches every project in the group.
- The rules in steps 4 and 5 admit only Maintainers, so that human accounts at the Developer role cannot move `main` or create seal tags. The sealer needs the Maintainer role to pass them.
- The username in a Git URL is any non-blank value. The token is the password.

The sealer uses `http://127.0.0.1:8929/$PROJECT.git` on the GitLab host, or
`http://$HOST.saola-matrix.ts.net:8929/$PROJECT.git` from another tailnet host.
The sealer is not packaged in this repository yet. Its token already sits in
`gitlab-kwyne-sealer-token` in the workstation SOPS file. No plaintext token
is installed by NixOS. Store a replacement token with `sops set --value-stdin`.

Revoke the temporary personal access token now.

### 7. Check that the project has one writer

GitLab Free protection rules name roles, not people. Individual users and groups
in these rules need Premium or Ultimate. A role rule admits that role and every
higher role. "Only the sealer" therefore means: no account other than the sealer
bot and `root` passes the rules.

`root` passes both rules, because it owns the namespace of the project. So does
every Owner or Maintainer, whether direct, inherited from a group, or shared
through a group. Each of them can also delete a protected tag in the UI or the API,
and can unprotect a rule. A GitLab administrator who is not a member does not pass
the role check, but can add itself as a member.

1. Open **Manage** > **Members**. The sealer bot must be the only Maintainer. Check inherited and shared members too.
2. Keep every human account at Developer or lower.
3. Treat `root` as the break-glass identity. It has the password and the authenticator of step 1.

Sources: [user permissions](https://docs.gitlab.com/19.3/user/permissions/),
[project members](https://docs.gitlab.com/19.3/user/project/members/).

### 8. Prove that a second identity fails

First let the sealer, or the sealer token, push the first commit. An empty
repository does not prove the rule, because GitLab applies the initial default
branch protection of step 2 there.

Then create a temporary project access token with the role **Developer** and the
scope `write_repository`. In a scratch clone, try both pushes. Each must fail with
the message shown. Then revoke the temporary token.

```bash
umask 077
credential_dir=$(mktemp -d)
trap 'rm -rf "$credential_dir"' EXIT
read -rs DEV_TOKEN        # paste the Developer token, then press Enter
printf '%s' "$DEV_TOKEN" > "$credential_dir/token"
unset DEV_TOKEN
cat > "$credential_dir/askpass" <<'ASKPASS'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' probe ;;
  *Password*) cat "$GITLAB_PROBE_TOKEN_FILE" ;;
  *) exit 1 ;;
esac
ASKPASS
chmod 0700 "$credential_dir/askpass"
export GITLAB_PROBE_TOKEN_FILE="$credential_dir/token"
export GIT_ASKPASS="$credential_dir/askpass" GIT_TERMINAL_PROMPT=0
URL="http://$HOST.saola-matrix.ts.net:8929/$PROJECT.git"
git push "$URL" HEAD:refs/heads/main
# remote: GitLab: You are not allowed to push code to protected branches on this project.
git tag -a -m probe kwyne/seal/probe && git push "$URL" refs/tags/kwyne/seal/probe
# remote: GitLab: You are not allowed to create this tag as it is protected.
```

Never embed a token in a Git URL or command argument. Use `GIT_ASKPASS` with
a mode-0600 temporary credential file. Delete the file and helper after use.

The sealer seals with one atomic push. `e2e-gitlab` runs it:

```bash
git tag -a -m "$RECEIPT_JSON" "kwyne/seal/$SEAL_ID" "$SHA"
git push --atomic --force-with-lease="refs/heads/main:$BASE_SHA" "$SEALER_URL" \
  "$SHA:refs/heads/main" "refs/tags/kwyne/seal/$SEAL_ID:refs/tags/kwyne/seal/$SEAL_ID"
```

If GitLab refuses one ref, it changes none of them. The VM check proves this for a
refused receipt: `main` stays where it was.

## Operate

### Token rotation

A project access token expires at midnight UTC on its expiry date (365 days at
most). Rotate the sealer token before then. Rotation creates a token with the
same role and scope and revokes the old one at once. `$TOKEN_ID` is the `id` from
step 6, or from the list at **Settings** > **Access tokens**.

Always pass `expires_at`. Without it, GitLab sets an expiry of one week
([rotate a project access token](https://docs.gitlab.com/19.3/api/project_access_tokens/#rotate-a-project-access-token)).

```bash
( umask 077
  api -X POST "$GITLAB/api/v4/projects/$PROJECT_ID/access_tokens/$TOKEN_ID/rotate" \
    -d "{\"expires_at\":\"$(date -d '+180 days' +%F)\"}" > sealer-token.json )
jq '{id, expires_at}' sealer-token.json
```

Use a personal access token with the `api` scope. The sealer token cannot rotate
itself, because it lacks that scope. Move the new `token` field into the secret
store of the sealer, delete the file, and keep the new `id` for the next rotation.

### Backup

`nori.backups.gitlab` runs the Restic job `gitlab` once a day (04:00 plus the
shared random delay of up to six hours). Each run first starts
`gitlab-backup.service`. That unit runs `gitlab-rake gitlab:backup:create` with
`BACKUP=dump`, while GitLab runs. The task writes the database dump and the
repository bundles into one file, `/var/lib/gitlab/backup/dump_gitlab_backup.tar`.
Restic copies the directory to the `onetouch` target (Backup transport row of the
placement table).

- The fixed name means one archive on disk. Restic keeps the history.
- The archive excludes the configuration and the secrets in the table above.
- The task does not back up Redis. The export is consistent when no Sidekiq job is pending or running ([backup guide](https://docs.gitlab.com/19.3/administration/backup_restore/backup_gitlab/)). With one automated writer, that is the normal state.
- If the export fails, `gitlab-backup.service` raises the `notify@` alert and the Restic run does not start. The failed export can leave an incomplete file on disk. Restore from a Restic snapshot, never from that file.
- The shared `restic-check-weekly` covers the `gitlab` repository, and the hourly freshness check alerts when the newest snapshot is older than 36 hours.

To run a backup now, on the GitLab host:

```bash
sudo systemctl start restic-backups-gitlab-onetouch.service
```

`e2e-gitlab` shows that a Restic run exports a fresh archive that contains the
database dump and the repository data.

### Restore

Read the [restore guide](https://docs.gitlab.com/19.3/administration/backup_restore/restore_gitlab/)
first. Two rules from it apply here:

- Restore only onto the same GitLab version and edition (CE) as the backup.
- The archive does not contain the secrets. SOPS provides the same values again.

`e2e-gitlab` runs steps 2 to 5 below on a live instance that it changed after the
backup. The changes are one more seal, an unprotected `main`, and a revoked
token. After the restore, `main`, its rule and the token are back, and the sealer
seals again.

No recovery drill with the real data exists yet. `docs/generated/recovery-evidence.md`
lists no evidence for `gitlab`. After the first activation, do a disposable
restore, as the [OneTouch runbook](onetouch-backup-cutover.md) does for the other
jobs, and record it in `src/inventory/recovery-evidence.nix`.

On new hardware, activate the same revision first. GitLab then starts as an empty
instance. Then run these steps on the GitLab host:

1. Put the archive at `/var/lib/gitlab/backup/dump_gitlab_backup.tar`, owned by `gitlab:gitlab`. Take it from a snapshot of the Restic repository `gitlab` on the `onetouch` target ([OneTouch runbook](onetouch-backup-cutover.md) for the transport).
2. Stop every GitLab unit. Stopping the target also stops Gitaly. PostgreSQL and Redis keep running:

   ```bash
   sudo systemctl stop gitlab.target
   ```

3. Start only what the restore needs. Wait for the Gitaly socket:

   ```bash
   sudo systemctl start gitlab-config.service gitaly.service gitlab-postgresql.service
   until [ -S /var/lib/gitlab/tmp/sockets/gitaly.socket ]; do sleep 1; done
   ```

4. Restore. The task loads the dump into the `gitlab` database and replaces the repositories:

   ```bash
   sudo -u gitlab -H gitlab-rake gitlab:backup:restore RAILS_ENV=production BACKUP=dump force=yes
   ```

5. Start GitLab again:

   ```bash
   sudo systemctl start gitlab.target
   ```

6. Check the instance. The readiness probe must print `200`. The doctor task checks that the database values decrypt with the current secrets ([check Rake tasks](https://docs.gitlab.com/19.3/administration/raketasks/check/#verify-database-values-can-be-decrypted-using-the-current-secrets)):

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8929/-/readiness
   sudo -u gitlab gitlab-rake gitlab:doctor:secrets RAILS_ENV=production
   ```

The protection rules and the sealer token come back with the database. Check them
with steps 4, 5 and 7 of [First-time setup](#first-time-setup).

A restore returns `main` and the seal tags to the state of the archive. That state
is up to a day old, and more when a run was late. Kwyne can hold receipts that
GitLab no longer has. Before the sealer runs again, compare the receipts of Kwyne
with `git ls-remote <url> 'refs/tags/kwyne/seal/*'` and with `main`. Do not let the
sealer reuse a seal id that Kwyne already reported.

### Upgrades

GitLab can only move through its required upgrade stops. In GitLab 19 they are
19.2, 19.5, 19.8 and 19.11. Allow the background migrations of a stop to finish
before the next step. The primary upgrade-path and release-note references,
along with the reviewed source and destination package versions, live in
[`src/services/gitlab/upgrade-policy.nix`](../../src/services/gitlab/upgrade-policy.nix).

A `nixpkgs` update moves the GitLab minor version without warning. The check
`eval-gitlab-authority` and the NixOS system assertion therefore reject a
package whose minor differs from the reviewed destination minor. Patch releases
within that minor pass. Keep the policy and this evidence synchronized when
reviewing a later minor.

The reviewed transition is GitLab **19.3.3 → 19.4.1**: system generation 521
used 19.3.3 and generation 522 used 19.4.1. GitLab's required 19.x stops are
19.2, 19.5, 19.8 and 19.11, so this transition did not skip a required stop.
The running 19.4.1 service returned readiness HTTP 200 during review.

The current CE backup archive is version 19.4.1, has no skipped components or
selective repository paths, and its latest recorded Restic snapshot is
`cb01cf40` at `2026-10-10T04:23:57+02:00`, covering
`/var/lib/gitlab/backup`. The restore procedure below is a full restore and does
not set `SKIP_REPOSITORIES_PATHS` or `REPOSITORIES_PATHS`. GitLab 19.4's selective
restore note therefore does not change this restore procedure. Geo is a
Premium/Ultimate feature and group SAML SSO is Premium/Ultimate; neither is
declared for this CE instance, so those 19.4 notes do not apply to the declared
configuration. The archive and snapshot metadata establish their recorded
version and coverage; they do not prove a database restore.

When the check fails:

1. Read the upgrade notes for the new minor version and every required stop between the installed and target versions.
2. If the package update skips a required stop, pin `nixpkgs` to a revision that carries the stop. Do not activate the skipping version.
3. Run a backup and confirm its Restic snapshot (`restic-backups-gitlab-onetouch.service`).
4. Update `upgrade-policy.nix` with the reviewed source and destination versions and primary GitLab documentation; record the runtime and backup evidence here.
5. Run `just check`, the host build and `just check-vm e2e-gitlab`. Then activate.

### Moving GitLab to another host

The manifest owns the placement. The same steps move GitLab from `workstation`
back to `adelie`, its intended home, and in any other direction:

1. Take a backup and keep the Restic snapshot.
2. In `src/services/gitlab/manifest.nix`, change the placement selector to the tag of the new host: `application-service-host` selects `adelie`, `primary-service-host` selects `workstation`.
3. Move the eight `gitlab-*` keys from the old to the new Secrets file (`sops decrypt` into `sops set --value-stdin`, without printing). Move the same values: a restore needs them. The age key of the new host must be a recipient of that file (`.sops.yaml`). Move the `secretspec.toml` entries to the profile of the new host.
4. Update the placement table above (Host, Listener, Secrets file, Activation, Backup transport and Intended home), `tests/eval/architecture-baseline.nix`, and `tests/eval/three-host-migration.nix`. That test pins the exact secrets and backup jobs of Adelie, so it names GitLab while GitLab runs there. Regenerate the generated docs.
5. Run `just check` and `just check-vm e2e-gitlab`, activate the new host, and restore the backup there ([Restore](#restore)).
6. Activate the old host to remove the service, and delete its state after the restore is verified.

### Triage

| Symptom | First check |
| --- | --- |
| `/-/readiness` is not 200 | `journalctl -u gitlab -u gitlab-workhorse -u gitaly -u gitlab-sidekiq -u gitlab-config -u gitlab-db-config -u gitlab-postgresql -u gitlab-proxy` |
| Tailnet clients cannot connect, loopback works | `journalctl -u gitlab-proxy`. The bind fails until `tailscale0` has its address. The restart policy retries with backoff and stops after 15 tries in an hour. Then run `sudo systemctl restart gitlab-proxy` |
| Migration errors after an update | Read the output of `gitlab-db-config.service`. Do not start `gitlab.service` over a failed migration |
| Backup alert | `journalctl -u gitlab-backup -u restic-backups-gitlab-onetouch`, then `df -h /var/lib/gitlab` |
| `root` password lost | `sudo -u gitlab gitlab-rake gitlab:password:reset` |

## Limits

- GitLab Free cannot name the sealer in a rule. The single writer comes from role membership (step 7), which is a manual check. `root` and every Owner or Maintainer pass the rules.
- The rule `kwyne/seal/*` does not protect the names `kwyne` and `kwyne/seal`. A Developer can create a tag with one of these names. Git then cannot create `kwyne/seal/<id>`, so sealing stops. Nothing is forged. To close the gap, protect `kwyne*` instead.
- The tailnet ACL decides which tailnet nodes reach port 8929. The repository does not hold the ACL ([ACL runbook](tailscale-acl.md)).
- GitLab has no Gatus probe, because it has no endpoint. A GitLab outage raises the `notify@` alert of the failed unit. Kwyne reports a seal request as `AwaitingAuthority` until GitLab returns.
- The database is the shared PostgreSQL instance. A PostgreSQL restart interrupts GitLab, and the reverse is not true.
- No recovery drill exists yet. `docs/generated/recovery-evidence.md` lists no evidence for `gitlab`.
