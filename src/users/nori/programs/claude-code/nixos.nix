{ config, lib, ... }:

/**
  Claude Code managed policy. ./default.nix (Home Manager) declares it as
  `nori.claudeCode.managedSettings`; Claude Code reads managed settings on
  Linux only from /etc/claude-code, which Home Manager cannot write. Hosts
  whose `nori` home does not import ./default.nix get no file.
*/
let
  managedSettings = lib.attrByPath [
    "home-manager"
    "users"
    "nori"
    "nori"
    "claudeCode"
    "managedSettings"
  ] null config;
in
{
  config = lib.mkIf (managedSettings != null) {
    environment.etc."claude-code/managed-settings.json".text = builtins.toJSON managedSettings;
  };
}
