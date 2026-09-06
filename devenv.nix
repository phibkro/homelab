{ config, pkgs, ... }:

{
  packages = with pkgs; [
    b3sum
    coreutils
    findutils
    git
    jq
    just
    shellcheck
    util-linux
  ];

  scripts.music-ingest-runtime.exec = ''
    exec bash "${config.devenv.root}/services/music-ingest/tests/runtime.sh"
  '';

  enterTest = ''
    bash "${config.devenv.root}/services/music-ingest/tests/runtime.sh"
  '';
}
