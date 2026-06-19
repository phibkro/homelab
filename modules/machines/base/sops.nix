{ inputs, ... }:

{
  /**
    sops-nix: encrypted secrets at rest in the repo, decrypted at
    activation time to /run/secrets/<name>. See secrets/README.md for
    the operator workflow.

    Each host decrypts using its own SSH ed25519 host key (derived
    to age form on the fly via ssh-to-age). The host's age public key
    must be listed in .sops.yaml and the secrets file must be
    re-encrypted (`sops updatekeys secrets/secrets.yaml`) before the
    host can decrypt anything.

    Add secrets in the consuming service module:
      sops.secrets.<name> = {};
    then reference `config.sops.secrets.<name>.path` from its *File option.
    `defaultSopsFile` below means the consumer doesn't restate `sopsFile`.
  */

  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    /*
      Default file for `sops.secrets.<name>` declarations across the
      repo. Per-secret `sopsFile` overrides if a service needs to keep
      its secrets in a separate file (rare).

      Absolute via `inputs.self` (the flake outPath) rather than the
      file-relative `../../../secrets/...` form — relative paths break
      silently when a module file gets moved (Phase 6a 2026-06-17
      shifted this very file two levels deeper and left the
      `../../secrets/...` reading pointing at a nonexistent path,
      surfaced as a build-time error on the next rebuild). The
      `secrets/` directory lives at repo root by convention; its
      absolute reference survives any future move of consumer files.
    */
    defaultSopsFile = inputs.self + "/secrets/secrets.yaml";
  };
}
