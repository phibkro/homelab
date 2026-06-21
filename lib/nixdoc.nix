/*
  Helpers for generating per-option reference markdown from NixOS
  module-system schemas. Used by every `flake-parts/packages/docs-*.nix`
  derivation.

  Pattern taken from rustdoc / jsdoc / Zig doc-comment generation,
  applied to NixOS module options + RFC 145 doc-comments.

  Inputs (passed by every consumer):
    pkgs — for runCommandLocal, gawk, nixdoc, gnused, nixosOptionsDoc
    lib  — for hasPrefix, escapeShellArg, etc.
    eval — a NixOS configuration whose `options` tree is documented.
           Currently `inputs.self.nixosConfigurations.workstation`
           because the workstation eval already pays its cost via
           `nix flake check`; piggybacking saves a duplicate evalModules.

  Outputs (function set):
    stripStorePrefix      — rewrite "Declared by" store paths to
                            repo-relative (byte-stability for docs-fresh)
    mkFileDocstring       — extract just the file-level RFC-145 doc-comment block
    mkNixdocSection       — RFC 145 doc-comment extraction via nixdoc
    mkSimpleDocsArtifact  — 2-section (overview + schema) generator
*/
{
  pkgs,
  lib,
  eval,
}:
let
  /*
    Rewrite per-option "Declared by" paths to repo-relative so the
    artifact is byte-stable across builds (the docs-fresh check would
    otherwise fire on every commit because the store path's hash
    differs each rebuild). The output is the literal repo-relative
    path (e.g. `modules/infra/networking`) — readable, stable, no
    regex syntax leaking into rendered docs.
  */
  stripStorePrefix =
    p:
    let
      s = toString p;
    in
    if lib.hasPrefix "/nix/store/" s then
      let
        m = builtins.match "/nix/store/[^/]*-source/(.*)" s;
      in
      if m == null then s else builtins.head m
    else
      s;

  /*
    Extract ONLY the file-level doc-comment block from a Nix file.
    Use for files that have a load-bearing module overview but no
    library API (hardware.nix, host config). The awk pass walks
    until it finds the first leading-`/**`-on-its-own-line, captures
    until the matching closing-marker line, and prints the body
    de-indented by 2 spaces (the standard nesting indent inside an
    RFC 145 doc-comment block).
  */
  mkFileDocstring =
    file:
    pkgs.runCommandLocal "file-docstring"
      {
        nativeBuildInputs = [ pkgs.gawk ];
      }
      ''
        awk '
          BEGIN { in_block = 0; printed = 0 }
          /^\/\*\*$/ && !printed { in_block = 1; next }
          /^\*\/$/ && in_block { in_block = 0; printed = 1; exit }
          in_block { sub(/^  /, ""); print }
        ' ${file} > $out
      '';

  /*
    Extract RFC 145 doc-comments from a Nix file via nixdoc.
    Output is a CommonMark fragment with the file's module-level
    docstring + per-attribute-binding docstrings (functions and
    values exported from the file's outermost attrset).

    Inputs: { file, description, category, prefix ? "homelab" }
      file         — path to a .nix file
      description  — title used in the first heading
      category     — section anchor (kebab-case)
      prefix       — namespace prefix (default "homelab")
  */
  mkNixdocSection =
    {
      file,
      description,
      category,
      prefix ? "homelab",
    }:
    pkgs.runCommandLocal "nixdoc-${category}"
      {
        nativeBuildInputs = [ pkgs.nixdoc ];
      }
      ''
        # File-level docstring first (nixdoc skips it as implicit
        # module-docstring rather than extractable content).
        cat ${mkFileDocstring file} > $out
        echo >> $out
        nixdoc --description ${lib.escapeShellArg description} \
               --prefix ${lib.escapeShellArg prefix} \
               --category ${lib.escapeShellArg category} \
               --file ${file} >> $out
      '';

  /*
    Minimal 2-section generator (module overview + per-option schema)
    used by single-schema `nori.<X>` docs. The richer multi-section
    generators (docs-lan-route, docs-topology, docs-capabilities)
    stay inline because their structure varies enough that a helper
    would over-fit.

    Inputs:
      name        — `nori.<name>` registry to render
      moduleFile  — path to default.nix of the concern (for nixdoc)
      category    — kebab-case section anchor

    Output: docs-${name} derivation; ./result is a CommonMark file
            matching docs/generated/${name}.md.
  */
  mkSimpleDocsArtifact =
    {
      name,
      moduleFile,
      category,
    }:
    let
      isOpt =
        opt:
        let
          inherit (opt) loc;
          prefix = builtins.head loc;
          second = if builtins.length loc >= 2 then builtins.elemAt loc 1 else "";
        in
        prefix == "nori" && second == name;
      optionsDoc = pkgs.nixosOptionsDoc {
        inherit (eval) options;
        transformOptions =
          opt:
          let
            base = if isOpt opt then opt else opt // { visible = false; };
          in
          base // { declarations = map stripStorePrefix base.declarations; };
        documentType = "none";
      };
      moduleDoc = mkNixdocSection {
        file = moduleFile;
        description = "${name} concern — overview";
        inherit category;
      };
    in
    pkgs.runCommandLocal "docs-${name}"
      {
        nativeBuildInputs = [ pkgs.gnused ];
      }
      ''
        cat > $out <<HEADER
        ---
        generated: true
        source: flake-parts/packages/docs-${name}.nix
        regenerate: nix build .#docs-${name}
        ---

        # \`nori.${name}\` — generated reference

        Two-section artifact: module overview (RFC 145 doc-comments
        from the concern's \`default.nix\`) + per-option schema
        (\`nixosOptionsDoc\` over the eval'd options tree). The
        concern file's path is shown in the per-option "Declared by"
        lines below.

        HEADER
        cat ${moduleDoc} >> $out
        echo >> $out
        cat >> $out <<'SCHEMA_HEADER'

        ## Option schema

        SCHEMA_HEADER
        # See docs-lan-route for the GFM-cleanup rationale.
        sed -e 's/\\\([.<>()]\)/\1/g' \
            -e 's|\[<nixpkgs/\([^]]*\)>\](https://github\.com/[^)]*)|`\1`|g' \
            -e 's|\[\([^]]*\)\](file://[^)]*)|`\1`|g' \
            ${optionsDoc.optionsCommonMark} >> $out
      '';
in
{
  inherit
    stripStorePrefix
    mkFileDocstring
    mkNixdocSection
    mkSimpleDocsArtifact
    ;
}
