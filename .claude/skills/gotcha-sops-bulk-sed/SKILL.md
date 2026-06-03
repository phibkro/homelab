---
name: gotcha-sops-bulk-sed
description: USE WHEN doing bulk find+sed / rg --replace / any text rename across `*.yaml` — sops uses key paths as AEAD additional-authenticated-data; renaming a key in clear-text corrupts every value under it (AAD mismatch → "Input authentication check failed"). EXCLUDE `secrets/` from the sweep, OR redo the rename inside `sops <file>`.
---

# Bulk find+sed on `*.yaml` corrupts sops-encrypted files

Sops encrypts each value with AES-GCM and uses the **key path as additional authenticated data (AAD)**. The key names in the YAML are clear-text, so a bulk text rename across `--include='*.yaml'` looks like it just works — `git diff` shows the rename land. But when sops next decrypts, the AAD computed from the new key path doesn't match the AAD that was baked into the ciphertext under the old key path, and every renamed entry fails to decrypt:

```
Failed to decrypt 'beszel-agent-key-workstation': Input authentication check failed
```

The ciphertext is intact; the file is unrecoverable in place.

Hit during the `nori-station` → `workstation` host rename (commit 7450daa) — the bulk sed across `*.yaml` was correct for `.sops.yaml` aliases (those keys aren't AAD-protected) but quietly corrupted `secrets/secrets.yaml`. Symptom didn't surface until the next build read a renamed secret.

**Recovery**: restore the file from the pre-corruption commit, then redo the rename **inside sops**:

```bash
git checkout <pre-corruption-sha> -- secrets/secrets.yaml
sops secrets/secrets.yaml
# rename keys in the editor — sops re-encrypts under the new key paths
```

**Prevention**: never include `secrets/secrets.yaml` (or any sops-encrypted YAML) in bulk text sweeps. Either:

- Exclude the secrets dir from the find sweep: `find . -name '*.yaml' -not -path './secrets/*'`
- Or stage the rename and `git checkout secrets/secrets.yaml` before committing, then redo it inside sops as above.

`.sops.yaml` itself is fine to sed — it contains aliases and recipients, not AEAD-protected ciphertext.
