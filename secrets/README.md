# Secrets

This directory holds **encrypted** secrets that ship in the repo. The
unencrypted plaintext never leaves your local sops session.

## Files in this directory

| File | What | Committed? |
|---|---|---|
| `secrets.yaml` | All secrets, encrypted with sops + age | yes (encrypted on disk) |
| `README.md` | this file | yes |

`.sops.yaml` lives at the repo root and declares which age public keys
can decrypt which files.

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

Each host decrypts using its **SSH ed25519 host key**, derived to age
form by sops-nix at activation time. To enroll a host, derive its age
public key from its SSH host key.

The cleanest way is to do the derivation **on the host itself** via
nix-shell — avoids needing `ssh-to-age` installed on the operator
machine:

```bash
# On a NixOS host (run on the host directly):
cat /etc/ssh/ssh_host_ed25519_key.pub \
  | nix shell nixpkgs#ssh-to-age --command ssh-to-age

# Or via SSH from the operator machine:
ssh user@host 'cat /etc/ssh/ssh_host_ed25519_key.pub \
  | nix shell nixpkgs#ssh-to-age --command ssh-to-age'
```

(If `ssh-to-age` is available locally — e.g. via `go install
github.com/Mic92/ssh-to-age/cmd/ssh-to-age@latest` or a brew tap — you
can also just `ssh-keyscan -t ed25519 <host> | ssh-to-age`.)

Add the resulting `age1...` value to `.sops.yaml` (both in the `keys:`
block and as an alias inside `creation_rules`), then run:

```bash
sops updatekeys secrets/secrets.yaml
```

…to re-encrypt with the expanded recipient set. Commit both
`.sops.yaml` and `secrets/secrets.yaml`.

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
`modules/.../sops.nix`, `.sops.yaml`, this README, and `sops.secrets.X`
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
