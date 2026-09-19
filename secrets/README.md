# Secrets

This directory holds **encrypted** secrets that ship in the repo. The
unencrypted plaintext never leaves your local sops session.

## Files in this directory

| File | What | Committed? |
|---|---|---|
| `secrets.yaml` | Homelab service secrets (Authelia, Vaultwarden, OIDC client hashes, restic password, …) | yes (encrypted on disk) |
| `apps.yaml` | Self-deployed personal-app secrets (TMDB tokens, Payload secrets, app database passwords) — separate file so app-key rotation doesn't churn `secrets.yaml`'s blame history, and so a future co-developer could be granted decrypt access to apps without exposing homelab plumbing | yes (encrypted on disk) |
| `README.md` | this file | yes |

`.sops.yaml` lives at the repo root and declares which age public keys
can decrypt which files. The current `path_regex: secrets/.*\.yaml$`
covers any new file under this directory automatically — to add a new
secrets file, just `sops secrets/<name>.yaml` and start adding keys.

## Per-secret file routing

`infra/common/nixos/sops.nix` sets `sops.defaultSopsFile =
../../secrets/secrets.yaml`, so secrets without an explicit
`sopsFile` declaration read from there. To route a secret at a
different file, override per-secret:

```nix
sops.secrets.tmdb-token = {
  sopsFile = ../../secrets/apps.yaml;
  owner = "filmder";
  mode = "0400";
};
```

Naming convention for `apps.yaml` keys: prefer **service-agnostic** names
(`tmdb-token`, not `filmder-tmdb-token`) when multiple projects could
plausibly consume the same secret. Use a project prefix only when the
secret is genuinely scoped to one project (`heim-payload-secret`,
`heim-revalidate-secret` — those mean nothing outside Payload CMS).

Convention:
- **Homelab service secrets** (used by `services/<service>/nixos.nix` to run the service itself) → `secrets.yaml` (default file, no override needed).
- **Self-deployed app secrets** (used by personal projects: filmder, heim, drinks, finnbydel) → `apps.yaml` (override `sopsFile` per declaration).

## SecretSpec

`secretspec.toml` declares credentials for operator tools. It stores no secret
values. Its `workstation` profile maps `EXA_API_KEY` to the encrypted
`exa-api-key` root key in `secrets/secrets.yaml`.

Run this command from the repository root to set or rotate the Exa key:

```bash
secretspec -f secretspec.toml set --profile workstation EXA_API_KEY
```

SecretSpec asks for the value in a masked prompt. It sends the value to SOPS,
which updates only the encrypted file.

## One-time bootstrap (do this once per editor machine)

On the Mac (or any machine that should be able to edit secrets):

```bash
# 1. Install tools (ssh-to-age isn't in homebrew core, but we don't
#    need it locally — see "host enrollment" below.)
brew install age sops

# 2. Generate your personal age keypair
mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Note the public key — the line in keys.txt that starts with
#   # public key: age1...
```

## One-time host enrollment (per host that needs to decrypt secrets)

Each host decrypts using its **SSH Ed25519 host key**, derived to age form
by sops-nix at activation time. Read the public host key at the physical
console or through an existing independently pinned SSH session. Record and
compare its fingerprint out of band before enrollment.

```bash
# Run on the independently verified NixOS host.
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
cat /etc/ssh/ssh_host_ed25519_key.pub \
  | nix shell nixpkgs#ssh-to-age --command ssh-to-age
```

`ssh-keyscan` can collect a candidate public key. It does not authenticate the
host and must not authorize SSH trust or a SOPS recipient.

Add the resulting `age1...` recipient only to the narrow `.sops.yaml`
creation rule for files that the host must decrypt. Do not add a minimal host
to the complete fleet or application secret corpus. Then update only those
files:

```bash
sops updatekeys secrets/<host-or-domain>.yaml
```

Inspect recipient metadata before committing. Removing a recipient from current
ciphertext does not revoke access to historical Git ciphertext. Rotate affected
credentials when the former recipient's private key was exposed or its access
was not authorized.

## Initial setup of secrets.yaml

After the placeholders in `.sops.yaml` are filled in:

```bash
sops secrets/secrets.yaml
# Editor opens with a fresh empty doc.
# Add at least one entry, e.g.:
#   placeholder: ok
# Save and quit. sops encrypts in place.
git add .sops.yaml secrets/secrets.yaml
git commit -m "feat(secrets): bootstrap sops with age-encrypted secrets.yaml"
```

## Day-to-day usage

```bash
# Edit secrets (decrypts in $EDITOR, re-encrypts on save):
sops secrets/secrets.yaml

# Add a new entry: just add a key under the YAML root.
# Reference it from a NixOS module:
#
#   sops.secrets.restic-password = {
#     sopsFile = ../../secrets/secrets.yaml;
#     owner = "root";
#     mode = "0400";
#   };
#
#   services.restic.backups.foo.passwordFile =
#     config.sops.secrets.restic-password.path;
```

After a rebuild, the secret materializes at `/run/secrets/<name>` on
the host with the declared owner / mode.

## Agent-access boundary

This repo's coding agent (Claude) writes the unencrypted *wiring*:
`infra/common/nixos/sops.nix`, `.sops.yaml`, this README, and `sops.secrets.X`
declarations inside service modules. The agent **must not have access
to your age private key** (`~/.config/sops/age/keys.txt`); without it,
encrypted secrets are gibberish to anything other than you and the
hosts listed as recipients.

Practically: don't paste the key into any chat/transcript and don't
commit it. The repo's `.gitignore` already excludes `~/.config/`-style
paths by virtue of being repo-relative, so the only failure mode is
accidental copy-paste.

## Recovery: lost age private key

If the Mac dies and you don't have the age private key backed up
elsewhere (1Password / hardware token / second machine), you can still
recover via any *other* enrolled recipient — e.g., decrypt on
workstation with its SSH host key, edit, and re-encrypt to a fresh
Mac age key. Or: re-create the secret values entirely (most are
recoverable from the upstream service: regenerate restic password,
re-issue tokens, etc.).
