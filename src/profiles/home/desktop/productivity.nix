{ inputs, pkgs, ... }:

/**
  General graphical work surfaces: browser, credentials, editors, and the
  Claude Desktop app.
*/
{
  imports = [ ../../../users/nori/programs/claude-desktop ];

  home.packages = [
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.bitwarden-desktop
    pkgs.zed-editor
    pkgs.vscode
  ];
}
