
# After installation: Configure Effect language tooling

Effect projects must install their Effect language tooling locally so the
editor, agent, and build use the project's exact TypeScript and Effect
versions. Read the local `typescript` version before choosing the tool.

For TypeScript 7 or newer, install `@effect/tsgo` and a compatible
project-local TypeScript release with the project's package manager. Then run
the pinned setup command non-interactively:

```sh
effect-tsgo setup --project tsconfig.json --non-interactive \
  --accept-defaults --apply --typescript --dependency-type devDependencies
```

Do not guess compatibility. Check the installed `@effect/tsgo` package's
supported TypeScript versions before changing either pin.

For TypeScript 6 or older, install `@effect/language-service` as a development
dependency, add `{ "name": "@effect/language-service" }` last in
`compilerOptions.plugins`, and ensure the editor uses the project-local
TypeScript installation.

OMP's TypeScript language-server router automatically selects a project-local
`effect-tsgo` executable for TypeScript 7+ projects. Verify the integration
with OMP's `lsp diagnostics` action on an Effect file; a floating
`Effect.log("probe")` expression must report the `floatingEffect` diagnostic.
