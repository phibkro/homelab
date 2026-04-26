{ inputs, ... }:

{
  # sops-nix: encrypted secrets at rest in the repo, decrypted at
  # activation time to /run/secrets/<name>. See secrets/README.md for
  # the operator workflow.
  #
  # Each host decrypts using its own SSH ed25519 host key (derived
  # to age form on the fly via ssh-to-age). The host's age public key
  # must be listed in .sops.yaml and the secrets file must be
  # re-encrypted (`sops updatekeys secrets/secrets.yaml`) before the
  # host can decrypt anything.
  #
  # No secrets are declared here yet. Add `sops.secrets.<name> = {};`
  # in the consuming service module, then reference
  # `config.sops.secrets.<name>.path` from its *File option. Each
  # `sops.secrets` declaration needs `sopsFile = ../../secrets/secrets.yaml`
  # until a project-wide `sops.defaultSopsFile` is set (left out for
  # now so the module is a no-op until secrets exist).

  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Default file for `sops.secrets.<name>` declarations across the
    # repo. Per-secret `sopsFile` overrides if a service needs to keep
    # its secrets in a separate file (rare).
    defaultSopsFile = ../../secrets/secrets.yaml;
  };
}
