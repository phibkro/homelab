{ lib }:
# Dev-shell composer. Each *.nix file in this directory (except this
# one) is a fragment: a function `{ pkgs, lib }: { buildInputs, env,
# shellHook, claude, depends, ... }` describing one *atomic* dev
# concern — a language toolchain, a build tool, a runtime, a service,
# or a tool-meta-config like claude-code. Consumers ask for a list of
# fragment names; the composer resolves transitive deps, dedupes,
# merges contributions, and returns a `pkgs.mkShell`.
#
# Same Reader+collected-Writer effect shape as `modules/effects/`:
# fragments declare contributions, the composer collects + interprets.
# Languages vs services vs tooling is a *folder-coupling* signal (none
# enforced today), not a type — every fragment has the same surface.
#
# Composability is the unifying claim: VSCode profiles overlap heavily
# but can't compose; per-project `nix develop` shells composed from
# atomic fragments give you exactly the toolchain you ask for, no
# more, with project-level Claude / Zed / etc. config materialized
# from the same module list.
let
  # Discover fragments by reading the directory. Adding a new fragment
  # is "create the file"; no central registry to update.
  isFragment = name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix";

  fragmentNames = map (lib.removeSuffix ".nix") (
    lib.attrNames (lib.filterAttrs isFragment (builtins.readDir ./.))
  );

  loadFragment =
    pkgs: name:
    import (./. + "/${name}.nix") {
      inherit pkgs lib;
    };

  # Topological closure over `depends`. A fragment can declare
  # `depends = [ "ts" ];` to require `ts` is loaded before it. Order is
  # deterministic; cycles are not detected (don't write cycles).
  resolveDeps =
    pkgs: requested:
    let
      step =
        visited: name:
        if lib.elem name visited then
          visited
        else
          let
            mod = loadFragment pkgs name;
            deps = mod.depends or [ ];
            withDeps = lib.foldl' step visited deps;
          in
          withDeps ++ [ name ];
    in
    lib.foldl' step [ ] requested;

  mkDevShell =
    pkgs:
    {
      modules ? [ ],
      extraInputs ? [ ],
      extraShellHook ? "",
    }:
    let
      # Validate before resolving so a typo gives "did you mean..." at
      # the call site, not an inscrutable `import` failure deeper in.
      invalid = lib.filter (n: !lib.elem n fragmentNames) modules;
      _validate = lib.assertMsg (invalid == [ ]) ''
        Unknown dev-shell modules: ${lib.concatStringsSep ", " invalid}.
        Available: ${lib.concatStringsSep ", " fragmentNames}.
      '';

      resolved = resolveDeps pkgs modules;
      fragments = map (loadFragment pkgs) resolved;

      buildInputs = lib.unique (lib.concatMap (m: m.buildInputs or [ ]) fragments) ++ extraInputs;

      # env merged right-bias — later fragments override earlier ones
      # on key collision. Resolution order is deterministic, so this is
      # stable across builds.
      envVars = lib.foldl' (acc: m: acc // (m.env or { })) { } fragments;

      shellHookBody = lib.concatStringsSep "\n" (
        (map (m: m.shellHook or "") fragments) ++ lib.optional (extraShellHook != "") extraShellHook
      );

      # Claude config: opt-in. The presence of the `claude-code`
      # fragment in the resolved module list is the consent signal —
      # without it, fragments' `claude.*` contributions are collected
      # silently and never written. Lets the same composer serve
      # projects shared with non-Claude-Code editors.
      claudeOpted = lib.elem "claude-code" resolved;
      claudeAllow = lib.unique (lib.concatMap (m: m.claude.permissions.allow or [ ]) fragments);
      claudeSettings = {
        "$schema" = "https://json.schemastore.org/claude-code-settings.json";
        permissions.allow = claudeAllow;
      };
      claudeFile = builtins.toFile "claude-settings.json" (builtins.toJSON claudeSettings);
      claudeMaterialize = lib.optionalString claudeOpted ''
        mkdir -p .claude
        ln -sfn ${claudeFile} .claude/settings.json
      '';
    in
    assert _validate;
    pkgs.mkShell (
      envVars
      // {
        inherit buildInputs;
        shellHook = ''
          ${claudeMaterialize}
          ${shellHookBody}
        '';
      }
    );
in
{
  inherit mkDevShell fragmentNames;
}
