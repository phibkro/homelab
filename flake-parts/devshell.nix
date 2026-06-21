/*
  `nix develop` shell for editing this repo. Dev environments are a
  per-project concern (devenv / direnv / nix shell), not a homelab-
  managed capability — each repo owns its own dev config. This shell
  gives `nix develop` here the tools needed to edit + format + lint
  the homelab itself.

  Uses `pkgsUnfree` rather than `pkgs` because the dev shell needs
  unfree packages (claude-code etc.) and the default `legacyPackages`
  honours the strict default. Hosts get unfree separately via
  `modules/machines/base/base.nix`; that path doesn't reach flake-
  level outputs like devShells.
*/
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      pkgsUnfree = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      devShells.default = pkgsUnfree.mkShell {
        buildInputs = with pkgsUnfree; [
          nixfmt
          nixfmt-tree
          statix
          deadnix
          nh
          ripgrep
        ];
      };
    };
}
