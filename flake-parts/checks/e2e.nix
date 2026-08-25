{ inputs, ... }:

{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks = {
        /**
          E2E — pi-alone smoke nixosTest. Boots a stripped-down
          pi-like config in QEMU + verifies the homelab services
          reach active state. The per-service scope (Phase 1
          through Phase 5+) is documented in
          docs/specs/2026-06-17-e2e-vm-simulation.md. Per
          docs/reference/testing-methodology.md this is layer 2
          (nixosTest) — pair with layer-1 eval tests at
          tests/eval/ for sub-second feedback during inner-loop
          iteration.
        */
        e2e-pi-smoke = import ../../tests/e2e-pi-smoke.nix { inherit pkgs lib inputs; };
        e2e-multi-host = import ../../tests/e2e-multi-host.nix { inherit pkgs lib inputs; };
        e2e-restic-backup = import ../../tests/e2e-restic-backup.nix { inherit pkgs lib inputs; };
        e2e-disk-alert = import ../../tests/e2e-disk-alert.nix { inherit pkgs lib inputs; };
        e2e-alerts-channel-auth = import ../../tests/e2e-alerts-channel-auth.nix {
          inherit pkgs lib inputs;
        };

        /**
          E2E — hypr-session user-journey nixosTest. Boots a real
          Hyprland (virtio-gpu + llvmpipe, structurally isolated
          from host DRM) and drives capture → save → compositor
          SIGKILL → restore against a fresh instance. Lives next to
          the scripts + bats suites it gates, unlike the tests/
          e2e-* set which exercise host configs.
        */
        e2e-hypr-session = import ../../modules/home/desktop/hypr-rice/hypr-session/tests/e2e-vm.nix {
          inherit pkgs;
        };
      };
    };
}
