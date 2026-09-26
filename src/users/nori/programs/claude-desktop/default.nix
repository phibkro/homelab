{ inputs, pkgs, ... }:

/**
  Claude Desktop — Anthropic's official Linux .deb, packaged by numtide's
  llm-agents input (the same pin that supplies Claude Code). Upstream wraps
  the app in a buildFHSEnv; both overrides below extend that package rather
  than repackaging it.

  Password store: Chromium's default `detect` does not recognise Hyprland and
  falls back to the plaintext-equivalent `basic` store. `gnome-libsecret`
  talks to the Secret Service that gnome-keyring provides
  (src/services/greetd/nixos.nix).

  Cowork: the app runs tasks in a QEMU/KVM VM. Before it offers the feature
  it probes, from inside the FHS sandbox (app.asar, Linux VM support check):

    qemu-system-x86_64       first match on PATH
    /usr/share/OVMF/OVMF_CODE_4M.fd or OVMF_CODE.fd; the vars template is
                             the same path with OVMF_CODE → OVMF_VARS
    /usr/libexec/virtiofsd or /usr/bin/virtiofsd; the bundled copy is used
                             only on Ubuntu 22.x
    /dev/kvm, /dev/vhost-vsock  readable and writable

  Upstream's FHS environment carries none of the userspace pieces, so its
  targetPkgs are extended with them. The device nodes are systemd's 0666
  static nodes, and bubblewrap binds /dev, so no group membership is needed.
*/

let
  inherit (pkgs.stdenv.hostPlatform) system;

  # OVMF ships the firmware under FV/; the app only looks in the Debian layout.
  coworkFirmware = pkgs.runCommand "claude-desktop-cowork-ovmf" { } ''
    mkdir -p $out/share/OVMF
    ln -s ${pkgs.OVMF.fd}/FV/OVMF_CODE.fd $out/share/OVMF/OVMF_CODE.fd
    ln -s ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd $out/share/OVMF/OVMF_VARS.fd
  '';

  claudeDesktop = inputs.llm-agents.packages.${system}.claude-desktop.override (args: {
    commandLineArgs = "--password-store=gnome-libsecret";
    buildFHSEnv =
      fhs:
      args.buildFHSEnv (
        fhs
        // {
          targetPkgs =
            fhsPkgs:
            fhs.targetPkgs fhsPkgs
            ++ [
              pkgs.qemu_kvm
              pkgs.virtiofsd
              coworkFirmware
            ];
        }
      );
  });
in
{
  home.packages = [ claudeDesktop ];
}
