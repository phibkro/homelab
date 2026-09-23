/*
  Generated reference for the `nori.harden` and `nori.gpu` schemas.

  Build:      nix build .#docs-capabilities
  Output:     ./result (CommonMark file)
  Committed:  docs/generated/capabilities.md
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
      packages.docs-capabilities =
        let
          isCapabilitiesOption =
            opt:
            let
              inherit (opt) loc;
              prefix = builtins.head loc;
              second = if builtins.length loc >= 2 then builtins.elemAt loc 1 else "";
            in
            prefix == "nori" && (second == "harden" || second == "gpu");
          optionsDoc = helpers.mkOptionsDoc isCapabilitiesOption;
          hardenDoc = helpers.mkNixdocSection {
            file = ../../../infra/common/nixos/service-hardening.nix;
            description = "Capabilities concern — overview";
            category = "capabilities";
          };
          gpuDoc = helpers.mkNixdocSection {
            file = ../../../infra/common/nixos/gpu.nix;
            description = "GPU access pattern";
            category = "capabilities-gpu";
          };
        in
        pkgs.runCommandLocal "docs-capabilities"
          {
            nativeBuildInputs = [ pkgs.gnused ];
          }
          ''
            cat > $out <<'HEADER'
            ---
            generated: true
            source: flake.nix § packages.docs-capabilities
            regenerate: nix build .#docs-capabilities
            ---

            # Capabilities — generated reference

            Module overviews + per-option schema for `nori.harden` and
            `nori.gpu`. Hand-curated cross-module synthesis (which
            services consume which capability, per-host driver
            choices) lives in the file-level doc-comments at
            `src/infra/common/nixos/{service-hardening,gpu}.nix`.

            HEADER
            cat ${hardenDoc} >> $out
            echo >> $out
            cat ${gpuDoc} >> $out
            echo >> $out
            cat >> $out <<'SCHEMA_HEADER'

            ## Option schema

            SCHEMA_HEADER
            # Normalize nixosOptionsDoc output to plain GFM.
            sed -e 's/\\\([.<>()]\)/\1/g' \
                -e 's|\[<nixpkgs/\([^]]*\)>\](https://github\.com/[^)]*)|`\1`|g' \
                -e 's|\[\([^]]*\)\](file://[^)]*)|`\1`|g' \
                ${optionsDoc.optionsCommonMark} >> $out
          '';
    };
}
