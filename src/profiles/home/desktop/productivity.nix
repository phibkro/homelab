{ inputs, pkgs, ... }:

/**
  General graphical work surfaces: browser, credentials, and editors.
*/
{
  home.packages = [
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.bitwarden-desktop
    pkgs.zed-editor
    pkgs.vscode
  ];
}
