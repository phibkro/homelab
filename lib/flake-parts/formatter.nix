/*
  Project formatter — nixfmt via the nixfmt-tree wrapper. Wired into
  `nix fmt` (also runs as `checks.format` in CI).
*/
_: {
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.nixfmt-tree;
    };
}
