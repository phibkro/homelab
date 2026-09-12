{ inputs, ... }:

{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks = lib.mapAttrs (_: check: check // { homelabCheckGroup = "vm"; }) {
        /**
          E2E — reusable entry-plane module contract. This QEMU-only
          NixOS fixture is not a Pi deployment; production Pi is Ansible-owned.
          It verifies the shared service modules reach active state. Phases 1
          through 7 are documented in
          docs/specs/2026-06-17-e2e-vm-simulation.md. Per
          docs/reference/testing-methodology.md this is layer 2
          (nixosTest) — pair with layer-1 eval tests at
          tests/eval/ for sub-second feedback during inner-loop
          iteration.
        */
        e2e-entry-plane-modules = import ../../../tests/e2e-pi-smoke.nix {
          inherit pkgs lib inputs;
        };
        e2e-multi-host = import ../../../tests/e2e-multi-host.nix { inherit pkgs lib inputs; };
        e2e-restic-backup = import ../../../tests/e2e-restic-backup.nix { inherit pkgs lib inputs; };
        e2e-disk-alert = import ../../../tests/e2e-disk-alert.nix { inherit pkgs lib inputs; };
        e2e-alerts-channel-auth = import ../../../tests/e2e-alerts-channel-auth.nix {
          inherit pkgs lib inputs;
        };
        e2e-music-ingest = import ../../../services/music-ingest/tests/nixos.nix {
          inherit pkgs lib;
        };
        e2e-desktop-settings-unix-ingress =
          import ../../../users/nori/programs/desktop/settings-service/test/unix-ingress.nix {
            inherit pkgs lib;
          };

        /**
          E2E — hypr-session user-journey nixosTest. Boots a real
          Hyprland (virtio-gpu + llvmpipe, structurally isolated
          from host DRM) and drives capture → save → compositor
          SIGKILL → restore against a fresh instance. Lives next to
          the scripts + bats suites it gates, unlike the tests/
          e2e-* set which exercise host configs.
        */
        e2e-hypr-session =
          import ../../../users/nori/programs/desktop/hypr-rice/hypr-session/tests/e2e-vm.nix
            {
              inherit pkgs;
            };
      };
    };
}
