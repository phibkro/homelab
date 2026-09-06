{ inputs, pkgs, ... }:

/**
  General graphical work surfaces: browser, credentials, and editors.
*/
{
  home.packages = [
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.bitwarden-desktop
    inputs.nixpkgs-master.legacyPackages.${pkgs.stdenv.hostPlatform.system}.zed-editor
    pkgs.vscode
  ];
}
