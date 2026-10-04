{ pkgs, ... }:

/**
  Tern — Stencil's multiplexing terminal (https://stencil.so/tern), beta.

  Beta builds are downloaded from build.stencil.so behind a Stencil login, so
  no public URL exists for fetchurl. `requireFile` pins the operator-downloaded
  tarball by hash; when the store lacks it, the build fails with the
  `nix-store --add-fixed` command below. The source is not a runtime
  dependency, so garbage collection may remove it later; re-add it when a
  nixpkgs change forces a rebuild.

  Upgrade: download the new tarball, bump `version` and `hash`
  (`nix hash file <tarball>`), add it to the store, rebuild.

  The binary is a prebuilt glibc ELF that links only libc/libstdc++ and
  dlopens its graphics and input stack, so those libraries go on the RPATH
  through `runtimeDependencies`. It locates `assets/` (bundled fonts) beside
  its resolved executable, so the release layout is kept under lib/tern and
  bin/tern is an exec wrapper. The wrapper appends glib's `gdbus`, which Tern
  runs to read the XDG settings portal (colour scheme, desktop settings).
  Self-update requires that writable layout; in the read-only store it
  cannot update itself, and versions change only through this file.
*/

let
  version = "0.4.1";
  tarball = "Tern-${version}-linux-x86_64.tar.gz";

  tern = pkgs.stdenv.mkDerivation {
    pname = "tern";
    inherit version;

    src = pkgs.requireFile {
      name = tarball;
      hash = "sha256-0AwxeySlXSnBRAZXpkSG0BCOEhlSYYQOCObhdqEznjQ=";
      message = ''
        Tern ${version} is a login-gated beta download from https://stencil.so/tern.
        Add the downloaded tarball to the Nix store, then rebuild:

          nix-store --add-fixed sha256 ~/Downloads/${tarball}
      '';
    };

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.makeWrapper
    ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    # dlopen targets observed in the binary: EGL/GLESv2, Vulkan, Wayland
    # client and EGL, xkbcommon, PAM.
    runtimeDependencies = [
      pkgs.libglvnd
      pkgs.vulkan-loader
      pkgs.wayland
      pkgs.libxkbcommon
      pkgs.pam
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/tern $out/bin
      cp -r tern assets $out/lib/tern/
      makeWrapper $out/lib/tern/tern $out/bin/tern \
        --suffix PATH : ${pkgs.lib.makeBinPath [ pkgs.glib.bin ]}
      runHook postInstall
    '';

    meta = {
      description = "Stencil's multiplexing terminal (beta)";
      homepage = "https://stencil.so/tern";
      license = pkgs.lib.licenses.unfree;
      platforms = [ "x86_64-linux" ];
      mainProgram = "tern";
      sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
    };
  };
in
{
  home.packages = [ tern ];
}
