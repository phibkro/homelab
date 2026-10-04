{ inputs, pkgs, ... }:

/**
  General graphical work surfaces: browser, credentials, editors, the
  Claude Desktop app, and the Tern terminal.
*/
{
  imports = [
    ../../../users/nori/programs/claude-desktop
    ../../../users/nori/programs/tern
  ];

  home.packages = [
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.bitwarden-desktop
    pkgs.zed-editor
    pkgs.vscode
  ];
}
