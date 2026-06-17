# Dev-shell composer (`mkDevShell` + `fragmentNames`) {#sec-functions-library-dev}


## `homelab.dev.mkDevShell` {#function-library-homelab.dev.mkDevShell}

Compose a `pkgs.mkShell` from a list of named dev-shell fragments.

Each fragment under `modules/dev/*.nix` contributes `buildInputs`,
environment variables, shell hooks, and optionally
`claude.permissions.allow` allowlist entries. The composer resolves
`depends` transitively, dedupes, merges contributions, and (if the
`claude-code` fragment is in the resolved set) materializes
`.claude/settings.json` whose `permissions.allow` is the union of
fragment contributions.

Consumer pattern: downstream project flakes reach this via
`inputs.lab.lib.mkDevShell` (or the homelab's own
`devShells.${system}.default`).

Unknown fragment names abort at the call site with a "did you mean"
list before resolution starts — typos fail loud, not deep inside an
`import`.

### Inputs

`pkgs`

: Nixpkgs binding for the target system. Pass `pkgsUnfree` if any
  requested fragment depends on an unfree package (e.g. `claude-code`).

Second argument (attrset):

`modules`

: List of fragment names (file basenames under `modules/dev/`).
  Order does not matter; transitive `depends` are resolved
  deterministically. Default `[ ]` — empty shell.

`extraInputs`

: Extra `buildInputs` to append to the fragment-contributed set.
  Use for one-off packages that don't justify a fragment.
  Default `[ ]`.

`extraShellHook`

: Extra `shellHook` body appended after fragment hooks. Runs in
  every entry to this shell. Default `""`.

### Type

```
mkDevShell :: pkgs -> {
  modules        ? [ String ],
  extraInputs    ? [ Derivation ],
  extraShellHook ? String,
} -> Derivation
```

### Examples

:::{.example}
#### `mkDevShell pkgsUnfree { modules = [ "nix" "claude-code" ]; }`

```nix
devShells.${system}.default = devLib.mkDevShell pkgsUnfree {
  modules = [ "nix" "claude-code" ];
};
=> pkgs.mkShell {
     buildInputs = [ nixfmt statix deadnix nh claude-code ];
     shellHook = ''
       mkdir -p .claude
       ln -sfn /nix/store/…-claude-settings.json .claude/settings.json
       …
     '';
   }
```
:::

## `homelab.dev.fragmentNames` {#function-library-homelab.dev.fragmentNames}

Live list of available dev-shell fragment names — file basenames
of `modules/dev/*.nix` minus this file.

Read this rather than hand-maintaining a static doc table:

```
nix eval .#lib.fragmentNames
```

### Type

```
fragmentNames :: [ String ]
```


