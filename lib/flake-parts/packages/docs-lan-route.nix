/*
  Generated reference for `nori.lanRoutes`. The hand-maintained
  docs/reference/network.md keeps the WHY + patterns; this artifact carries
  the evaluated option schema.

  Build:      nix build .#docs-lan-route
  Output:     ./result (CommonMark file)
  Committed:  docs/generated/lan-route.md
*/
{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    let
      eval = inputs.self.nixosConfigurations.workstation;
      helpers = import ../../nixdoc.nix { inherit pkgs lib eval; };
    in
    {
      packages.docs-lan-route =
        let
          isLanRouteOption =
            opt:
            let
              inherit (opt) loc;
              prefix = builtins.head loc;
              second = if builtins.length loc >= 2 then builtins.elemAt loc 1 else "";
            in
            prefix == "nori" && (second == "lanRoutes" || second == "domain" || second == "lanIp");
          optionsDoc = helpers.mkOptionsDoc isLanRouteOption;
          moduleDoc = helpers.mkNixdocSection {
            file = ../../../infra/common/nixos/routes.nix;
            description = "Networking concern — overview";
            category = "networking";
          };
        in
        pkgs.runCommandLocal "docs-lan-route"
          {
            nativeBuildInputs = [ pkgs.gnused ];
          }
          ''
            cat > $out <<'HEADER'
            ---
            generated: true
            source: flake.nix § packages.docs-lan-route
            regenerate: nix build .#docs-lan-route
            ---

            # `nori.lanRoutes` — generated reference

            Two-section artifact:

             1. Networking-concern overview — RFC 145 doc-comments
                extracted from `infra/common/nixos/routes.nix`.
             2. `nori.lanRoutes.<name>.*` schema reference — option
                fields extracted via `nixosOptionsDoc`.

            The hand-written `network.md` keeps the WHY + patterns;
            this artifact carries the WHAT (schema details).

            HEADER
            cat ${moduleDoc} >> $out
            echo >> $out
            # nixosOptionsDoc emits docbook-flavoured escapes + nixpkgs
            # github links (the auto-rewrite assumes paths are nixpkgs-
            # relative). Post-process to plain GFM: strip backslash
            # before non-markdown-special chars; replace both link forms
            # ([<nixpkgs/path>](https://github.com/…) and stray
            # [path](file://path)) with inline-code `path`.
            sed -e 's/\\\([.<>()]\)/\1/g' \
                -e 's|\[<nixpkgs/\([^]]*\)>\](https://github\.com/[^)]*)|`\1`|g' \
                -e 's|\[\([^]]*\)\](file://[^)]*)|`\1`|g' \
                ${optionsDoc.optionsCommonMark} >> $out
          '';
    };
}
