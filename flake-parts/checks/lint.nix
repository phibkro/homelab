{ inputs, ... }:

{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks =
        let
          /*
            nori.lint dispatcher — lowers the TOML rule registry to one
            `grep`-shaped flake-check derivation. See lint/
            default.nix for the schema + the data-vs-control-plane
            rationale (rules are pure data in TOML; the dispatcher is
            the program that consumes them).
          */
          lintLib = import ../../lint { inherit lib pkgs; };
          lintRules = (builtins.fromTOML (builtins.readFile ../../lint/rules.toml)).rules;
        in
        {
          /*
            Repo-convention enforcement (Reader+Writer applied to lint).

            Rules live as data in lint/rules.toml (the Reader);
            lint/default.nix is the dispatcher that lowers the
            rule registry to a single bash check (the Writer). Adding a
            rule = one `[rules.<name>]` block in the TOML.

            Replaces the prior `forbidden-patterns` flake check that
            carried 9 rules in lint/checks/forbidden-patterns.sh.
            Behavior parity verified: same patterns, same scopes, same
            allowlists.
          */
          lint = lintLib.makeLintCheck {
            rules = lintRules;
            sourceRoot = ../..;
          };
        };
    };
}
