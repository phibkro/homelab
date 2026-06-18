{ lib, ... }:

/**
  Test fixture — disable sops decryption for nixosTest VMs.

  Real hosts decrypt sops secrets at activation time using the host's
  SSH ed25519 key. nixosTest VMs have an ephemeral SSH key generated
  at test start; the host's age public key isn't a sops recipient
  for the real `secrets/secrets.yaml`, so activation would fail at
  the sops-install step.

  This fixture force-empties `sops.secrets` and `sops.templates` so
  the activation script becomes a no-op. Consuming service modules
  that READ `config.sops.secrets.<X>.path` would still error if they
  expected a specific secret to exist — those services are out of
  scope for the Phase 1 minimal smoke (blocky + gatus + beszel-hub,
  none of which read sops at runtime). Phase 2+ broadens scope and
  will replace this with a real test-fixture sops key + ciphertext.

  Belongs under tests/fixtures/ per the e2e VM simulation spec
  (docs/specs/2026-06-17-e2e-vm-simulation.md § Q1).
*/

{
  sops.secrets = lib.mkForce { };
  sops.templates = lib.mkForce { };

  # Service modules read `config.sops.secrets.<X>.path` to wire their
  # *File options; with sops force-emptied those reads fail. Override
  # the specific consumers in scope for Phase 1 to point at /dev/null
  # (gatus only needs the env file to exist; no env vars are required
  # to reach `gatus.service active`).
  services.gatus.environmentFile = lib.mkForce "/dev/null";
}
