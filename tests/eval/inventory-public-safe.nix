{
  inputs,
  lib,
  ...
}:

/**
  Negative public-inventory boundary test.

  The pure inventory is intentionally consumable by documentation, deployment,
  and status tooling. Recursively reject implementation paths, derivations,
  secret-shaped keys, and common secret material markers before the catalog
  grows beyond the Jellyfin pilot.
*/

let
  inventory = inputs.self.lib.noriInventory;

  forbiddenKeys = [
    "apiKey"
    "credential"
    "credentials"
    "environmentFile"
    "password"
    "passwordFile"
    "privateKey"
    "runtimeModule"
    "secret"
    "secrets"
    "sops"
    "token"
  ];

  forbiddenStringFragments = [
    "/run/secrets/"
    "ENC["
    "sops.secrets"
  ];

  violationsAt =
    path: value:
    if builtins.isPath value then
      [ "${path}: contains a Nix path" ]
    else if lib.isDerivation value then
      [ "${path}: contains a derivation" ]
    else if builtins.isAttrs value then
      lib.concatMap (
        name:
        let
          childPath = if path == "" then name else "${path}.${name}";
        in
        lib.optional (lib.elem name forbiddenKeys) "${childPath}: secret-shaped key"
        ++ violationsAt childPath value.${name}
      ) (lib.attrNames value)
    else if builtins.isList value then
      lib.concatLists (lib.imap0 (index: item: violationsAt "${path}[${toString index}]" item) value)
    else if builtins.isString value then
      lib.concatMap (
        fragment:
        lib.optional (lib.hasInfix fragment value) "${path}: contains forbidden marker '${fragment}'"
      ) forbiddenStringFragments
    else
      [ ];

  violations = violationsAt "" inventory;
in
if violations == [ ] then
  "ok — public inventory contains no implementation paths or secret-shaped data"
else
  throw ''
    Public inventory boundary violation(s):
    ${lib.concatStringsSep "\n" (map (violation: "- ${violation}") violations)}
  ''
