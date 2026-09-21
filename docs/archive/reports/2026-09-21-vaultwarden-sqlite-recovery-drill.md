# Vaultwarden SQLite recovery drill — September 21, 2026

This drill proved the logical SQLite recovery path for Vaultwarden. It used
source revision `0e8a176590a2`. Times are UTC unless specified otherwise.

## Scope

Vaultwarden runs on Adelie and uses SQLite. Its backup declaration in
`services/vaultwarden/nixos.nix` uses `VACUUM INTO` before each Restic run. The
preparation step writes a transaction-consistent database to
`/var/backup/vaultwarden/db.sqlite3`.

The drill used the deployed Restic transport and its pinned workstation host
identity. It restored the latest OneTouch snapshot into a new directory on
Adelie. It did not replace or write the production database.

## Fresh snapshot and restore

The normal `restic-backups-vaultwarden-onetouch.service` unit completed
successfully at 00:37:24. Its preparation step completed four seconds earlier.
The prepared database size was 278,528 bytes.

Restic selected snapshot `a779c327`, created at 00:37:21. It restored 12 files
and directories with a total size of 577.640 KiB. The snapshot contained both
the live service directory and the prepared logical database.

For the application test, the restored service directory was copied to a new
temporary directory. The prepared database replaced the restored raw database
in that copy. The production directory remained unchanged.

## Isolation

The restored application ran in a private Linux network namespace. Only its
loopback interface was enabled. Therefore, the process could not contact
Authelia, SMTP, the internet, or another host.

The temporary process used:

- the deployed Vaultwarden `1.37.2` binary;
- a temporary data directory owned by the `vaultwarden` user;
- loopback address `127.0.0.1` and port `18222`;
- disabled SSO, registration verification, and web-vault delivery;
- no production environment file or OIDC secret.

The process received a graceful termination after the checks.

## Application and database result

| Check | Result |
|---|---|
| SQLite integrity before startup | `ok` |
| Restored users | 1 |
| Restored ciphers | 0 |
| Restored attachments | 0 |
| Vaultwarden startup | Rocket listening on `127.0.0.1:18222` |
| `/alive` | HTTP `200` |
| `/api/config` | HTTP `200`; object type `config` |
| SQLite integrity after shutdown | `ok` |

The public configuration response identified Vaultwarden and reported web
client version `2026.6.0`. The service log identified server version `1.37.2`.

The restored database contains one account but no saved ciphers or attachments.
Thus, this drill proves schema, account-state, migration, startup, and read
behavior. It cannot prove item decryption or attachment access until such data
exists.

## Cleanup and production check

The temporary process, application directory, restore directory, response
files, and logs were removed. Port `18222` had no listener after cleanup.

The production `vaultwarden.service` remained active. Its production `/alive`
endpoint returned HTTP `200` after the drill.

## Evidence boundary

This drill establishes the logical SQLite state model:

```text
live SQLite → VACUUM INTO → Restic snapshot → disposable restore
            → prepared DB installed in temporary state → real application
```

It does not establish:

- master-password or OIDC login;
- cipher decryption or attachment recovery;
- production replacement;
- PostgreSQL, files-only, or native-export recovery;
- complete Adelie host reconstruction;
- every-file data-block integrity for all repositories.

The next state-model drill should restore the Miniflux PostgreSQL dump into an
isolated PostgreSQL instance and verify feed and user rows through Miniflux.
