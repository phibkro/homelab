# Secrets

This directory contains encrypted production values. Plaintext must stay inside
SOPS, SecretSpec, or the final authorized process.

## Authority domains

| File | Authority | Recipients |
|---|---|---|
| `network.yaml` | Shared Akkar Wi-Fi credential | Mac, workstation user, workstation host, Adelie host |
| `shared-runtime.yaml` | Runtime values consumed by both NixOS hosts | Mac, workstation user, workstation host, Adelie host |
| `workstation-runtime.yaml` | Values materialized for workstation services | Mac, workstation user, workstation host |
| `adelie-runtime.yaml` | Values materialized for Adelie services | Mac, workstation user, Adelie host |
| `operator-tools.yaml` | Interactive infrastructure-control credentials | Mac, workstation user |

`.sops.yaml` has one explicit creation rule for each file. There is no
production catch-all rule. A new encrypted file requires a new explicit rule.

SOPS access applies to the complete file. A per-secret `sopsFile` declaration
selects a source for sops-nix, but it does not restrict file decryption.

## SecretSpec

The root `secretspec.toml` is the operator interface for these files. It stores
no values. Provider aliases route each name to its authoritative SOPS file.

Use a masked SecretSpec prompt to set or rotate a value:

```bash
secretspec set --profile workstation EXA_API_KEY
secretspec set --profile adelie OIDC_NEWS_CLIENT_SECRET
secretspec set --profile wifi AKKAR_WPA_PSK
```

Do not pass the value as the final command argument. A command argument enters
shell history and can be visible in the process list.

Cloudflare commands use SecretSpec scopes. Each scope injects only the values
used by that Alchemy stack. `secretspec run --scope` also removes excluded
manifest names inherited from the parent environment.

The Pi uses `infra/pi/secretspec.toml`. Its Keyring and environment providers
remain separate from these SOPS files:

```bash
cd infra/pi
devenv shell -- secretspec check --profile production
```

The Pi `deployment` scope excludes the Tailscale enrollment key. The
`enrollment` scope includes only that key.

The Pi provider is the only authority for its Caddy ACME and DDNS tokens.
Workstation SOPS must not copy those values. If a NixOS host selects the Caddy
or DDNS runtime adapter, its composition must supply that host's SOPS source.

## NixOS routing

`infra/common/nixos/sops.nix` sets `workstation-runtime.yaml` as the shared
default. Adelie overrides the default with `adelie-runtime.yaml`. A shared or
host-specific value must declare its file explicitly.

The Wi-Fi module uses:

```nix
sops.secrets.wifi-akkar-psk.sopsFile =
  inputs.self + "/secrets/network.yaml";
```

After activation, sops-nix writes each selected value under `/run/secrets`.
The consuming declaration must set the narrow owner, group, and mode.

## OIDC client rotation

Raw OIDC client values belong to the host that runs the client. PBKDF2
verifier hashes belong to the Pi identity provider. Do not store both in one
recipient domain.

For an existing client such as `news`:

1. Generate a random raw value in the operator password manager.
2. Store it through the consuming host's SecretSpec profile:

   ```bash
   secretspec set --profile adelie OIDC_NEWS_CLIENT_SECRET
   ```

3. Generate the verifier through Authelia's masked terminal prompt:

   ```bash
   nix shell nixpkgs#authelia --command \
     authelia crypto hash generate pbkdf2 \
       --variant sha512 \
       --iterations 310000
   ```

4. Store the displayed verifier through the Pi SecretSpec profile:

   ```bash
   cd infra/pi
   devenv shell -- secretspec set \
     --profile production \
     OIDC_NEWS_CLIENT_SECRET_HASH
   ```

5. Run the scoped checks and deployment plan before activation.

The raw value must not enter command arguments, terminal output, temporary
plaintext files, or Git.

## Editor enrollment

Create a personal age identity on an authorized administration machine:

```bash
mkdir -p ~/.config/sops/age
chmod 700 ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

Back up the private identity in the approved password manager. Add only its
public `age1...` recipient to the required `.sops.yaml` rules.

## Host enrollment

Each NixOS host derives an age identity from its SSH Ed25519 host key. Observe
and compare the SSH fingerprint through an independently trusted channel.

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
cat /etc/ssh/ssh_host_ed25519_key.pub \
  | nix shell nixpkgs#ssh-to-age --command ssh-to-age
```

`ssh-keyscan` can collect a candidate key. It cannot establish host identity.

Add the verified age recipient only to files the host must decrypt. Then update
those files:

```bash
sops updatekeys secrets/<domain>.yaml
```

Removing a recipient from current ciphertext does not revoke historical Git
access. Rotate affected credentials if prior access was unauthorized or the
private key was compromised.

## Safe ciphertext migration

Move one value through an anonymous pipe:

```bash
sops decrypt --extract '["source-key"]' secrets/source.yaml \
  | jq -Rs 'rtrimstr("\n")' \
  | sops set --value-stdin secrets/target.yaml '["target-key"]'
```

Verify the destination before you remove the source. Never put plaintext in a
shell variable, command substitution, clipboard, temporary file, or transcript.

## Recovery

If an editor identity is lost, recover through another enrolled recipient.
Decrypt from that trusted machine and re-encrypt to a new verified recipient.
If no trusted recipient remains, rotate the upstream credentials.
