{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "oh-my-pi";
  version = "17.2.3";

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${finalAttrs.version}/omp-linux-x64";
    hash = "sha256-uqWGZO1OUQygTLdW4njWt11LzOVi4UdMDJM39SXGs/o=";
  };

  dontUnpack = true;

  # Keep the Bun standalone byte-for-byte. autoPatchelfHook rewrites its ELF
  # container and makes the executable boot as plain Bun instead of OMP.

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/omp"
    runHook postInstall
  '';

  meta = {
    description = "Coding agent with native IDE, subagent, and multi-provider support";
    homepage = "https://omp.sh";
    changelog = "https://github.com/can1357/oh-my-pi/blob/v${finalAttrs.version}/packages/coding-agent/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "omp";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
