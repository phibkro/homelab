{ inputs, ... }:

{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      /*
        ── Generated docs prototype (Sprint 6 exploration) ─────────────

        Generates per-option reference markdown for the `nori.lanRoutes`
        effect via nixpkgs' `nixosOptionsDoc`. The hand-maintained
        docs/reference/network.md keeps the WHY + patterns; this
        generated artifact carries the WHAT (schema details). Pattern
        taken from rustdoc/jsdoc/Zig doc-comment generation, applied to
        NixOS module options.

        Why this entry point (workstation's eval):
          * nixosOptionsDoc renders options against an EVALUATED
            options tree; the workstation config already pays the eval
            cost via `nix flake check`, so we piggyback rather than
            spinning up a scratch evalModules (which would need to stub
            out nori.hosts to satisfy lan-route's `default` derivation
            of nori.lanIp).
          * `transformOptions` filters to the lan-route surface only —
            nori.lanRoutes.* + nori.domain + nori.lanIp. Everything
            else gets `visible = false`, which the renderer drops.

        Build with: `nix build .#docs-lan-route`
        Output:     ./result (CommonMark file)
      */
      packages =
        let
          eval = inputs.self.nixosConfigurations.workstation;

          /**
            Extract RFC 145 doc-comments from a Nix file via nixdoc.
            Output is a CommonMark fragment with the file's
            module-level docstring + per-attribute-binding docstrings
            (functions and values exported from the file's outermost
            attrset).

            Inputs: { file, description, category, prefix ? "homelab" }
              file         — path to a .nix file
              description  — title used in the first heading
              category     — section anchor (kebab-case)
              prefix       — namespace prefix (default "homelab")

            Output: derivation whose `out` is a CommonMark file.
          */
          /*
            Extract ONLY the file-level doc-comment block from a Nix file.
            Use for files that have a load-bearing module overview but no
            library API (hardware.nix, host config). The awk pass walks
            until it finds the first leading-`/**`-on-its-own-line, captures
            until the matching closing-marker line, and prints the body
            de-indented by 2 spaces (the standard nesting indent inside
            an RFC 145 doc-comment block).
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

          mkNixdocSection =
            {
              file,
              description,
              category,
              prefix ? "homelab",
            }:
            pkgs.runCommandLocal "nixdoc-${category}"
              {
                nativeBuildInputs = [
                  pkgs.nixdoc
                ];
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
          # stripStorePrefix + mkSimpleDocsArtifact moved to lib/nixdoc.nix
          # (consumed by flake-parts/packages/docs-{backups,fs,replicas}.nix).
          # The inline docs-{lan-route,topology,capabilities} below still
          # define their own stripStorePrefix copies for now; they'll move
          # to flake-parts/packages/ in a subsequent phase.
        in
        {
          # docs-backups, docs-fs, docs-replicas extracted to
          # flake-parts/packages/docs-{backups,fs,replicas}.nix

          docs-lan-route =
            let
              isLanRouteOption =
                opt:
                let
                  inherit (opt) loc;
                  prefix = builtins.head loc;
                  second = if builtins.length loc >= 2 then builtins.elemAt loc 1 else "";
                in
                prefix == "nori" && (second == "lanRoutes" || second == "domain" || second == "lanIp");
              /*
                Rewrite per-option "Declared by" paths to repo-relative so
                the artifact is byte-stable across builds (the docs-fresh
                check would otherwise fire on every commit because the
                store path's hash differs each rebuild). The output is the
                literal repo-relative path (e.g. `modules/infra/networking`)
                — readable, stable, no regex syntax leaking into rendered
                docs.
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
              optionsDoc = pkgs.nixosOptionsDoc {
                inherit (eval) options;
                transformOptions =
                  opt:
                  let
                    base = if isLanRouteOption opt then opt else opt // { visible = false; };
                  in
                  base // { declarations = map stripStorePrefix base.declarations; };
                documentType = "none";
              };
              moduleDoc = mkNixdocSection {
                file = ../../modules/infra/networking/default.nix;
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
                    extracted from `modules/infra/networking/default.nix`.
                 2. `nori.lanRoutes.<name>.*` schema reference — option
                    fields extracted via `nixosOptionsDoc`.

                The hand-written `network.md` keeps the WHY + patterns;
                this artifact carries the WHAT (schema details).

                HEADER
                cat ${moduleDoc} >> $out
                echo >> $out
                # nixosOptionsDoc emits docbook-flavoured escapes + nixpkgs   # multi-line: ok (bash inside heredoc)
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

          /*
            ── Generated topology docs (Stage 2 pressure test) ───────────────

            Two-section artifact:

              §1  Hosts at a glance — walks `config.nori.hosts` values,
                  emits the per-host overview table that topology.md used
                  to carry as hand-maintained prose.

              §2  Topology registry schema — nixosOptionsDoc reference for
                  `nori.hosts.<name>.*` option fields. Tells you what an
                  `inventory/hosts.nix` identity entry must declare.

            §1 is built from VALUES (config.nori.hosts.workstation.hardware
            etc.); §2 is built from the OPTIONS tree. nixosOptionsDoc handles
            the second; the first is hand-rolled string concatenation in Nix
            because it has no equivalent built-in (the renderer emits option
            docs, not config dumps).

            Entry point uses workstation's eval (same rationale as
            docs-lan-route above — piggyback on an eval that already pays
            its cost in `nix flake check`).

            Build with: `nix build .#docs-topology`
          */
          docs-topology =
            let
              hosts = eval.config.nori.hosts;
              hostNames = lib.attrNames hosts;

              # Render a single host's primaryJob — multi-line prose, paragraph
              # in markdown source, gets joined with <br> in the table cell.
              renderJob = job: lib.replaceStrings [ "\n" ] [ " " ] (lib.strings.trim job);

              renderRoleCell =
                host: if host.roleOneLiner == "" then "`${host.role}`" else "`${host.role}` (${host.roleOneLiner})";

              hostRow =
                name:
                let
                  h = hosts.${name};
                in
                "| **${name}** | ${h.codename} | ${renderRoleCell h} | `${h.tailnetIp}` | ${
                  if h.lanIp == null then "—" else "`${h.lanIp}`"
                } | ${h.hardware} | ${renderJob h.primaryJob} |";

              hostsTable = lib.concatStringsSep "\n" (
                [
                  "| Host | Codename | Role | Tailnet | LAN | Hardware | Primary job |"
                  "|---|---|---|---|---|---|---|"
                ]
                ++ map hostRow hostNames
              );

              isHostsOption =
                opt:
                let
                  inherit (opt) loc;
                  prefix = builtins.head loc;
                  second = if builtins.length loc >= 2 then builtins.elemAt loc 1 else "";
                in
                prefix == "nori" && second == "hosts";

              # See docs-lan-route above for why we strip the store
              # hash from "Declared by" paths.
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
              optionsDoc = pkgs.nixosOptionsDoc {
                inherit (eval) options;
                transformOptions =
                  opt:
                  let
                    base = if isHostsOption opt then opt else opt // { visible = false; };
                  in
                  base // { declarations = map stripStorePrefix base.declarations; };
                documentType = "none";
              };
              machinesDoc = mkNixdocSection {
                file = ../../modules/machines/default.nix;
                description = "Topology — overview";
                category = "topology";
              };
              # Per-host hardware narrative — extracts JUST the file-level
              # /** */ block from each modules/machines/<host>/hardware.nix.
              # We DON'T want the per-attribute nixdoc extraction here (each
              # `swapDevices = [ ]` setting has a `/* */` rationale comment
              # that becomes noisy clutter when extracted). The file-level
              # docstring carries the module-as-whole story; that's all we
              # need.
              hostHardwareDoc = name: mkFileDocstring (../../modules/machines + "/${name}/hardware.nix");
              hardwareSection = pkgs.runCommandLocal "hardware-section" { } (
                lib.concatStringsSep "\n" (
                  [
                    "cat <<'HEADER' > $out"
                    "## Per-host hardware posture"
                    ""
                    "HEADER"
                  ]
                  ++ map (n: "cat ${hostHardwareDoc n} >> $out") (lib.sort builtins.lessThan hostNames)
                )
              );
            in
            pkgs.runCommandLocal "docs-topology"
              {
                nativeBuildInputs = [ pkgs.gnused ];
              }
              ''
                cat > $out <<'HEADER'
                ---
                generated: true
                source: flake.nix § packages.docs-topology
                regenerate: nix build .#docs-topology
                ---

                # Topology — generated reference

                Auto-derived from the `nori.hosts` schema + values in
                `inventory/hosts.nix`. Do not hand-edit; the
                hand-curated overview lives at `docs/reference/topology.md`
                (kept parallel for the generated-vs-handwritten coverage
                experiment).

                HEADER
                cat ${machinesDoc} >> $out
                echo >> $out
                cat ${hardwareSection} >> $out
                echo >> $out
                cat >> $out <<'GLANCE_HEADER'

                ## Hosts at a glance

                GLANCE_HEADER
                cat >> $out <<'TABLE'
                ${hostsTable}
                TABLE
                cat >> $out <<'SCHEMA_HEADER'

                ## Registry schema (`nori.hosts.<name>.*`)

                What an `inventory/hosts.nix` identity entry must declare to
                satisfy the schema. Schema lives in `modules/infra/hosts.nix`.

                SCHEMA_HEADER
                # See docs-lan-route for the GFM-cleanup rationale.
                sed -e 's/\\\([.<>()]\)/\1/g' \
                    -e 's|\[\([^]]*\)\](file://[^)]*)|`\1`|g' \
                    ${optionsDoc.optionsCommonMark} >> $out
              '';

          /*
            ── Generated capabilities docs ─────────────────────────────────

            Two-section artifact:

              §1  Capabilities concern overview — file-level docstring
                  from modules/infra/capabilities/default.nix (nori.harden
                  + FS-namespace adapter narrative).

              §2  GPU access pattern — file-level docstring from
                  modules/infra/capabilities/gpu.nix (the live driver
                  split, the per-service GPU consumer table, the
                  registry shape rationale) plus the nori.gpu and
                  nori.harden option schemas.

            Build with: `nix build .#docs-capabilities`
          */
          docs-capabilities =
            let
              isCapabilitiesOption =
                opt:
                let
                  inherit (opt) loc;
                  prefix = builtins.head loc;
                  second = if builtins.length loc >= 2 then builtins.elemAt loc 1 else "";
                in
                prefix == "nori" && (second == "harden" || second == "gpu");
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
              optionsDoc = pkgs.nixosOptionsDoc {
                inherit (eval) options;
                transformOptions =
                  opt:
                  let
                    base = if isCapabilitiesOption opt then opt else opt // { visible = false; };
                  in
                  base // { declarations = map stripStorePrefix base.declarations; };
                documentType = "none";
              };
              hardenDoc = mkNixdocSection {
                file = ../../modules/infra/capabilities/default.nix;
                description = "Capabilities concern — overview";
                category = "capabilities";
              };
              gpuDoc = mkNixdocSection {
                file = ../../modules/infra/capabilities/gpu.nix;
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
                `modules/infra/capabilities/{default,gpu}.nix`.

                HEADER
                cat ${hardenDoc} >> $out
                echo >> $out
                cat ${gpuDoc} >> $out
                echo >> $out
                cat >> $out <<'SCHEMA_HEADER'

                ## Option schema

                SCHEMA_HEADER
                # See docs-lan-route for the GFM-cleanup rationale.            # multi-line: ok (bash inside heredoc)
                sed -e 's/\\\([.<>()]\)/\1/g' \
                    -e 's|\[<nixpkgs/\([^]]*\)>\](https://github\.com/[^)]*)|`\1`|g' \
                    -e 's|\[\([^]]*\)\](file://[^)]*)|`\1`|g' \
                    ${optionsDoc.optionsCommonMark} >> $out
              '';
        };
    };
}
