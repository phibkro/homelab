/*
  Claw Patrol — agent egress firewall.  Upstream has no Nix package or
  flake, so keep the immutable source pin and Go module closure here.

  The optional dashboard is deliberately not built: the gateway API and
  policy engine are the deployment surface in this repository.  Go's
  embed directive still needs a dist directory, so the build supplies a
  static placeholder without pulling a Node/Deno dependency graph into
  the package.
*/
{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      clawpatrol = pkgs.buildGoModule rec {
        pname = "clawpatrol";
        version = "0-unstable-2026-07-21";

        src = pkgs.fetchFromGitHub {
          owner = "denoland";
          repo = "clawpatrol";
          rev = "438b1bcd9ddd9ac1cb6ecb6abdb6667f6b035363";
          hash = "sha256-YUheXD5xzXwrHT5HmrgGF+19o8NvcaxMdJW7BQCdKiU=";
        };

        patches = [
          ./clawpatrol-ssh-env-slots.patch
          ./clawpatrol-default-deny-relay.patch
        ];

        subPackages = [ "cmd/clawpatrol" ];
        vendorHash = "sha256-9HIqm4PmmiDMFjBMqIlMtKlUBlKyKGkMWlDLSOoyVXE=";

        # Upstream's command-package tests build throwaway external plugins
        # with a second Go module download and exercise mount namespaces.
        # Both are intentionally unavailable in a Nix build sandbox. Runtime
        # policy/config validation is covered by the NixOS module check.
        doCheck = false;

        preBuild = ''
          mkdir -p dashboard/dist
          cp dashboard/login.html dashboard/dist/index.html
        '';

        ldflags = [
          "-s"
          "-w"
        ];

        meta = {
          description = "Security firewall for agents";
          homepage = "https://github.com/denoland/clawpatrol";
          license = lib.licenses.mit;
          mainProgram = "clawpatrol";
          platforms = lib.platforms.linux;
        };
      };
      paguBoxUnwrapped = inputs.pagu-box.packages.${pkgs.stdenv.hostPlatform.system}.default;
      paguBoxClawpatrol = pkgs.writeShellApplication {
        name = "pagu-box";
        runtimeInputs = [ clawpatrol ];
        text = ''
          profile="default"
          args=("$@")
          i=0
          while [ "$i" -lt "''${#args[@]}" ]; do
            case "''${args[$i]}" in
              --profile=*) profile="''${args[$i]#--profile=}" ;;
              --profile)
                i=$((i + 1))
                profile="''${args[$i]:-}"
                ;;
              --) break ;;
            esac
            i=$((i + 1))
          done

          if [ "$profile" != strict ]; then
            exec ${paguBoxUnwrapped}/bin/pagu-box "$@"
          fi

          # Claw Patrol publishes a CA, not a secret. Its run command builds
          # ca-bundle.crt immediately before it execs pagu-box, so make both
          # public trust files visible through strict's tmpfs HOME. Credential
          # bytes remain owned by the gateway service user.
          ca="$HOME/.clawpatrol/ca.crt"
          caBundle="$HOME/.clawpatrol/ca-bundle.crt"
          if [ ! -r "$ca" ]; then
            echo "pagu-box: Claw Patrol is not enrolled; run 'clawpatrol join <gateway-url>' first" >&2
            exit 1
          fi
          exec clawpatrol run -- \
            ${paguBoxUnwrapped}/bin/pagu-box \
              --ro-allow "$ca" \
              --ro-allow "$caBundle" \
              "$@"
        '';
      };
    in
    {
      packages.clawpatrol = clawpatrol;
      packages.pagu-box-clawpatrol = paguBoxClawpatrol;

      checks.pagu-box-clawpatrol = pkgs.runCommandLocal "pagu-box-clawpatrol-check" { } ''
        ${paguBoxClawpatrol}/bin/pagu-box --help > /dev/null
        grep -F 'clawpatrol run' ${paguBoxClawpatrol}/bin/pagu-box
        grep -F 'ca-bundle.crt' ${paguBoxClawpatrol}/bin/pagu-box
        grep -F 'Claw Patrol is not enrolled' ${paguBoxClawpatrol}/bin/pagu-box
        touch "$out"
      '';

      checks.clawpatrol-config =
        pkgs.runCommandLocal "clawpatrol-config-check"
          {
            nativeBuildInputs = [ clawpatrol ];
          }
          ''
            clawpatrol validate ${inputs.self.nixosConfigurations.workstation.config.nori.clawpatrol.configFile}
            touch "$out"
          '';
    };
}
