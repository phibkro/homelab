{
  config,
  inputs,
  pkgs,
  ...
}:

let
  chatlogPackage = inputs.chatlog.packages.${pkgs.stdenv.hostPlatform.system}.chatlog;
in
/**
  Workstation realization of the Chatlog product.

  The external flake owns the package, service module, ingestion policy, and
  user interfaces. This profile owns only machine policy: installation,
  loopback service activation, and the stable operator data path. Keeping it
  separate from agentic-workstation.nix prevents corpus lifecycle concerns
  from coupling every harness or desktop module to Chatlog.
*/
{
  imports = [ inputs.chatlog.homeManagerModules.default ];

  home.packages = [ chatlogPackage ];

  services.chatlog-workbench = {
    enable = true;
    package = chatlogPackage;
    dataRoot = "${config.xdg.dataHome}/chatlog";
    host = "127.0.0.1";
    port = 4789;
    allowAnnotations = true;
    annotationOrigins = [ "https://chatlog.home.phibkro.org" ];
  };
}
