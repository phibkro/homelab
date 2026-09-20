---
summary: Replace broad SOPS corpora and broad SecretSpec command injection with recipient-scoped files and command-scoped resolution.
date: 2026-09-20
status: implemented; not activated, deployed, published, or rotated
owner: operator
---

# Secret authority isolation

## Goal

Each persisted secret has one encrypted source, each SOPS file has an explicit recipient set, and each SecretSpec-launched command receives only the secrets it uses.

## Authority model

- SOPS file rules define which operator and host identities can decrypt a ciphertext corpus.
- SecretSpec profiles define how named values resolve from their authoritative providers.
- SecretSpec scopes define which values enter one command environment.
- sops-nix declarations define which runtime account can read each materialized file.
- Nix profiles and workload placement do not substitute for cryptographic recipient isolation.

## Encrypted domains

### Network

`secrets/network.yaml` contains `wifi-akkar-psk`. Its recipients are the Mac recovery identity, workstation user identity, workstation host, and Adelie host.

Workstation and Adelie reference this same ciphertext entry. Pi remains outside this SOPS domain; a later Pi Wi-Fi implementation can receive the value through a dedicated SecretSpec command without creating another persisted SOPS copy.

### Workstation runtime

`secrets/workstation-runtime.yaml` contains values that current workstation Nix evaluation materializes for system or user services. Its recipients are the Mac recovery identity, workstation user identity, and workstation host.

The Pi and Adelie host identities cannot decrypt this file. sops-nix owner and mode declarations remain the runtime reader boundary.

### Operator tools

`secrets/operator-tools.yaml` contains credentials used only by interactive infrastructure-control commands. Its recipients are the Mac recovery identity and workstation user identity. Host identities cannot decrypt it.

Cloudflare Alchemy commands resolve this file through SecretSpec. They must not decrypt a complete SOPS document directly into their environment.

## SecretSpec command scopes

The root manifest provides distinct provider aliases for network, workstation runtime, and operator tools.

Cloudflare scopes expose only:

- main Hindsight stack: Cloudflare control token and Hindsight bearer token;
- Herdr projects stack: Cloudflare control token and Herdr bearer token;
- Herdr relay: Herdr bearer token;
- development share: Cloudflare control token.

Pi keeps one production profile so provider addresses do not change. Its command scopes are:

- `deployment`: every value consumed by production plan or deploy, excluding Tailscale enrollment;
- `enrollment`: only `TAILSCALE_AUTH_KEY`.

`secretspec run --scope` is required at each command boundary because it also removes manifest-declared secrets inherited from the parent environment.

## Migration safety

Plaintext may flow only through anonymous pipes between SOPS processes. It must not enter command arguments, shell variables, terminal output, clipboard history, temporary plaintext files, or Git.

The old encrypted files remain until every selected value exists in its destination and all consumers reference the new domains. The final tree removes the superseded encrypted files and stale catch-all recipient rule.

This migration does not rotate credentials. Removing a recipient from current ciphertext does not revoke access to historical Git ciphertext. Rotation is separate work if a former recipient was unauthorized or compromised.

## Acceptance

1. `.sops.yaml` has explicit rules for all three production files and no production catch-all.
2. Pi cannot decrypt workstation runtime or operator-tool ciphertext with its enrolled age identity.
3. Adelie can decrypt only the network production file.
4. Workstation and Adelie evaluate one `wifi-akkar-psk` source from `network.yaml`.
5. Workstation evaluation routes every materialized non-network secret to `workstation-runtime.yaml`.
6. Cloudflare package commands use SecretSpec scopes instead of `sops exec-env`.
7. Pi plan/deploy do not receive `TAILSCALE_AUTH_KEY`; Pi enrollment receives no other manifest secret.
8. SecretSpec schemas validate without reading values.
9. SOPS reports every production file as encrypted and recipient metadata matches its rule.
10. Workstation and Adelie closures build, and the focused repository checks pass.
11. No host activation, deployment, secret rotation, remote publication, or provider mutation occurs.
