{
  description = "nori infrastructure (NixOS) — workstation and future lab hosts";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    /*
      flake-parts — module system FOR flakes. Same composition shape
      (one input → multiple outputs) that `nori.<X>` modules use at the
      NixOS layer, applied to the flake-output layer. Lets each check /
      package / devshell live in its own file with a typed interface.
      Eval doc: docs/plans/2026-06-21-dendritic-evaluation.md.
    */
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    /*
      nixpkgs master — used ONLY for cherry-picking individual packages
      whose nixos-unstable channel cut lags far behind upstream. Don't
      mass-overlay from this; resolve specific lags one package at a
      time. Currently consumed by:
        modules/machines/desktop/apps.nix → zed-editor (nixos-unstable shipping
          v0.232.3 as of 2026-05-07, master shipping v1.1.6; months of
          Linux/Wayland/file-watcher fixes in the gap)
    */
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    /*
      Per-user config (desktop phase). Pinned to release-26.05 to match
      nixpkgs. Mac homeConfiguration rides this too — 26.05 was
      announced as the LAST nixpkgs release supporting Intel Mac
      (x86_64-darwin), so this pin is the natural Mac end-of-line:
      either keep 26.05 indefinitely or migrate Mac off nixpkgs.
    */
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    /*
      Zen browser. Not in nixpkgs; consumed via upstream community flake.
      `.default` tracks rolling Twilight; pivot to `.beta` or `.specific`
      if Twilight churn becomes annoying.
    */
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";

    /*
      snappy-switcher — Hyprland alt-tab overlay. Not in nixpkgs;
      upstream ships a flake. Bindings + daemon autostart live in
      modules/machines/workstation/hyprland.lua (ALT+Tab MRU global, SUPER+Tab
      workspace-local).
    */
    snappy-switcher.url = "github:OpalAayan/snappy-switcher";
    snappy-switcher.inputs.nixpkgs.follows = "nixpkgs";

    /*
      hermes-agent — NousResearch's coding agent (uv2nix flake). We
      consume `packages.default` (bare CLI) for interactive use inside
      `box`; `messaging` / `full` variants available if we ever wire
      Discord/Telegram or external memory providers.

      No GitHub credential is plumbed into hermes by design — see the
      security note in modules/home/claude-code/default.nix; operator-driven
      claude-code remains the only path to commit/push.
    */
    hermes-agent.url = "github:NousResearch/hermes-agent";
    hermes-agent.inputs.nixpkgs.follows = "nixpkgs";

    /*
      ollama package overlaid from nixpkgs `release-26.05` (which
      carries 0.30.5 via backport of #527892 + #528150). The main
      `nixpkgs` input above tracks the `nixos-26.05` channel, which
      currently lags behind release-26.05 on ollama. Drop this input
      + the `services.ollama.package` override in
      modules/services/ollama.nix when the channel catches up.
    */
    nixpkgs-ollama.url = "github:NixOS/nixpkgs/release-26.05";

    /*
      Stylix — single-input system-wide theming. Same
      Reader+collected-Writer shape as the lab's `nori.<X>` effect
      family — fits cleanly. Workstation imports the NixOS module
      via modules/machines/desktop/stylix.nix.
    */
    stylix.url = "github:danth/stylix/release-26.05";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    /*
      Third-party Claude Code skill sources — pinned via flake.lock,
      consumed as plain source trees by modules/home/claude-code/default.nix.
      Update via `nix flake update --update-input <name>`. Not flakes
      themselves, hence flake = false.
    */
    superpowers.url = "github:obra/superpowers";
    superpowers.flake = false;
    caveman.url = "github:juliusbrussee/caveman";
    caveman.flake = false;
    /*
      Anthropics' public Agent-Skills repo. We only consume the
      frontend-design subdir today; the rest (xlsx, pptx, mcp-builder,
      etc.) is one extra symlink away if/when needed.
    */
    anthropics-skills.url = "github:anthropics/skills";
    anthropics-skills.flake = false;
    /*
      masonjames/Shadcnblocks-Skill — gives Claude Code expert
      knowledge of 2,500+ shadcn/ui blocks. Single `shadcn-ui` skill.
    */
    shadcn.url = "github:masonjames/Shadcnblocks-Skill";
    shadcn.flake = false;
    /*
      kepano/obsidian-skills — multi-skill (defuddle, json-canvas,
      obsidian-bases, obsidian-cli, obsidian-markdown). We only
      consume obsidian-markdown today.
    */
    obsidian-skills.url = "github:kepano/obsidian-skills";
    obsidian-skills.flake = false;
    /*
      mattpocock/skills — Matt Pocock's engineering + productivity
      skill collection. Pinned to v1.0.1 (the explicit versioned
      release; tag-pinning catches breaking renames in his model-
      invocation slots). Replaces several skills previously
      hand-vendored under modules/home/claude-code/skills/
      (improve-codebase-architecture, tdd, diagnose, grill-with-docs).
      The curated import list in default.nix excludes personal/
      and in-progress/ subdirs; misc/ is selective.
    */
    mattpocock-skills.url = "github:mattpocock/skills/v1.0.1";
    mattpocock-skills.flake = false;
    /*
      shadcn/improve — single `improve` skill. Audits a codebase
      as a senior advisor and writes self-contained implementation
      plans for cheaper-model executors to run. Read-only on
      source code by design.
    */
    shadcn-improve.url = "github:shadcn/improve";
    shadcn-improve.flake = false;

    /*
      nix-community/impermanence — "erase your darlings" mechanism.
      Opt-in per host. Consumed by machines/pavilion (agent quarantine):
      pavilion uses btrfs-rollback rather than tmpfs root (3.6 GB RAM
      ceiling) — the impermanence module is FS-agnostic; the rollback
      service in pavilion's default.nix provides the clean state on disk.
    */
    impermanence.url = "github:nix-community/impermanence";

    /*
      Context-engineering tooling (Claude Code) — three small third-party
      tools that shift token-heavy operations off the conversation budget.
      See /srv/share/projects/CLAUDE.md for the cross-project explainer +
      modules/home/claude-code/default.nix for the wireup.

      * tilth — MCP server, structural file reads via tree-sitter (replaces
        Read on large files). Has its own flake; we just consume its
        packages.default. Pre-1.0 (v0.9.0 as of 2026-06); pin via flake.lock.
      * rtk — CLI proxy filtering boilerplate from noisy commands. Single
        Rust binary, no upstream flake.nix; built via rustPlatform inside
        modules/home/claude-code/default.nix.
      * stacklit — generates ~250-token codebase index per repo. Go binary;
        built via buildGoModule from cmd/stacklit/ (the npm wrapper just
        downloads prebuilt binaries — impure).
    */
    tilth.url = "github:jahala/tilth";
    tilth.inputs.nixpkgs.follows = "nixpkgs";
    rtk-src.url = "github:rtk-ai/rtk";
    rtk-src.flake = false;
    stacklit-src.url = "github:glincker/stacklit";
    stacklit-src.flake = false;

    /*
      pagu-box — cross-platform sandboxed launcher for any process.
      Pinned to the LOCAL checkout (path:) rather than github so the
      homelab picks up uncommitted operator edits without a push +
      `flake update` cycle each iteration. pagu-box is operator-owned
      and lives alongside the homelab; pinning local matches the dev
      model. Flip to `github:phibkro/pagu-box` if someone else needs
      to consume this flake on a machine without that checkout.
    */
    pagu-box.url = "path:/srv/share/projects/pagu-box";
    pagu-box.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      flake-parts,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      /*
        ── Machines ──────────────────────────────────────────────────
        Enumeration, identity registry, and mkHost wrapper all live
        at modules/machines/default.nix. flake.nix imports the
        factory; it returns `nixosConfigurations`. See the module
        for the schema, the registry, and the rationale.
      */
      machinesModule = import ./modules/machines {
        inherit lib inputs;
      };

      /*
        ── Home configurations ──────────────────────────────────────
        Standalone home-manager entries for non-NixOS machines (Mac).
        Lives at modules/home/default.nix.
      */
      homeModule = import ./modules/home {
        inherit inputs nixpkgs home-manager;
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      /*
        `systems` here is the host on which `nix flake check` /
        formatter / etc run — not the target platform of any host.
        Each host's hardware.nix sets nixpkgs.hostPlatform; mkHost
        no longer hardcodes system, so pi (aarch64-linux) and
        workstation (x86_64-linux) coexist cleanly.
      */
      systems = [ "x86_64-linux" ];

      # Per-output flake-parts modules — each file declares its own
      # perSystem or flake fragment. Adding a new output = new file +
      # one line here (or auto-discovery via haumea if the tree grows).
      imports = [
        ./flake-parts/formatter.nix
      ];

      # System-agnostic outputs — don't vary across builder platforms.
      flake = {
        inherit (machinesModule) nixosConfigurations;
        inherit (homeModule) homeConfigurations;
      };

      # System-keyed outputs (devShells, formatter, packages, checks).
      # flake-parts provides pkgs/lib/system via the perSystem function
      # arguments; everything inside is implicitly per-system.
      perSystem =
        {
          pkgs,
          lib,
          system,
          ...
        }:
        let
          /*
            A second pkgs binding with `allowUnfree = true` for the dev
            shell — needed because `claude-code` is unfree and the
            default `legacyPackages.${system}` honours the strict
            default. Hosts get unfree separately via
            `modules/machines/base/base.nix` setting `nixpkgs.config.allowUnfree`,
            but that path doesn't reach flake-level outputs like devShells.
          */
          pkgsUnfree = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
            };
          };
        in
        {
          /*
            Minimal dev shell for editing this repo. Dev environments are
            a per-project concern (devenv / direnv / nix shell), not a
            homelab-managed capability — each repo owns its own dev
            config. This shell gives `nix develop` here the tools needed
            to edit + format + lint the homelab itself.
          */
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

          # formatter moved to flake-parts/formatter.nix

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
              /*
                Shared between every docs-* derivation: rewrite per-option
                "Declared by" paths to repo-relative so the artifact is
                byte-stable across builds (the docs-fresh check would
                otherwise fire on every commit because the store path's
                hash differs each rebuild). Output: the literal repo-relative
                path (e.g. `modules/infra/networking`) — readable, stable,
                no regex syntax leaking into rendered docs.
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
                mkSimpleDocsArtifact — minimal 2-section generator
                (module overview + per-option schema) used by the
                single-schema nori.<X> docs. The richer multi-section
                generators (docs-lan-route, docs-topology, docs-capabilities)
                stay inline because their structure varies enough that a
                helper would over-fit.

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
                    source: flake.nix § packages.docs-${name}
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
              # Single-schema docs use the shared helper above.
              docs-backups = mkSimpleDocsArtifact {
                name = "backups";
                moduleFile = ./modules/infra/backup/default.nix;
                category = "backups";
              };
              docs-fs = mkSimpleDocsArtifact {
                name = "fs";
                moduleFile = ./modules/infra/storage/default.nix;
                category = "fs";
              };
              docs-replicas = mkSimpleDocsArtifact {
                name = "replicas";
                moduleFile = ./modules/infra/storage/replication.nix;
                category = "replicas";
              };

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
                    file = ./modules/infra/networking/default.nix;
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
                      identityFor entry must declare.

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
                    file = ./modules/machines/default.nix;
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
                  hostHardwareDoc = name: mkFileDocstring (./modules/machines + "/${name}/hardware.nix");
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

                    Auto-derived from `nori.hosts` schema + `identityFor` values
                    in `modules/machines/default.nix`. Do not hand-edit; the
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

                    What an `identityFor` entry must declare to satisfy the schema.
                    Schema lives in `modules/infra/hosts.nix`; values live in
                    `modules/machines/default.nix`.

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
                    file = ./modules/infra/capabilities/default.nix;
                    description = "Capabilities concern — overview";
                    category = "capabilities";
                  };
                  gpuDoc = mkNixdocSection {
                    file = ./modules/infra/capabilities/gpu.nix;
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

          # Quality gates. `nix flake check` validates host evals + the
          # checks below; `nix flake show .#checks` is the live index.
          checks =
            let
              /*
                Files under modules/services/ that aren't user-facing services —
                folder aggregators, the *arr group's `media`-bootstrap helper,
                and the backup-cluster framework. Both `every-service-has-<X>`
                checks share this baseline; per-check additions (e.g. samba's
                /srv exception, notify@'s template-only file) are appended
                below at the call site.
              */
              baseNonServicePatterns = [
                "*/default.nix"
                "modules/services/arr/shared.nix"
                /*
                  Route-only — declares nori.lanRoutes for the hermes
                  daemon, which itself is a home-manager user service
                  under home/hermes/. No NixOS-scope service, state, or
                  hardening surface.
                */
                "modules/services/hermes.nix"
              ];
              /**
                Generate a `case` glob from a list of patterns, joined with
                `|`. Used at the head of each scanner loop to skip framework
                / aggregator files.
              */
              mkCasePattern = ps: lib.concatStringsSep "|" ps;

              /*
                nori.lint dispatcher — lowers the TOML rule registry to one
                `grep`-shaped flake-check derivation. See lint/
                default.nix for the schema + the data-vs-control-plane
                rationale (rules are pure data in TOML; the dispatcher is
                the program that consumes them).
              */
              lintLib = import ./lint { inherit lib pkgs; };
              lintRules = (builtins.fromTOML (builtins.readFile ./lint/rules.toml)).rules;
            in
            {
              # cd into the source so statix picks up `statix.toml` (looked up
              # from the working directory, not the path argument).
              statix = pkgs.runCommandLocal "statix" { } ''
                cd ${./.}
                ${pkgs.statix}/bin/statix check . > $out
              '';

              /*
                --no-lambda-pattern-names: NixOS module convention is to
                declare `{ config, lib, pkgs, ... }:` even when not all are
                used; tolerate that. Still flags genuine unused
                let-bindings and other dead code.
              */
              deadnix = pkgs.runCommandLocal "deadnix" { } ''
                ${pkgs.deadnix}/bin/deadnix --fail --no-lambda-pattern-names ${./.}
                touch $out
              '';

              format = pkgs.runCommandLocal "format" { } ''
                ${pkgs.nixfmt-tree}/bin/treefmt --ci --tree-root ${./.}
                touch $out
              '';

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
                sourceRoot = ./.;
              };

              /*
                Migration-era checks (path-coherence, multi-line-comments)
                were demoted to one-off scripts under lint/checks/ — invoked
                via `just check-migration` on demand. Their catch-rate at
                steady state is near-nil; the convention is set and new
                agents inherit it. The flake check overhead they imposed on
                every `nix flake check`/`nix develop`/CI run wasn't paying
                for itself. Re-promote if a future restructure phase pulls
                them back to non-zero catch rate.

                doc-coherence was deleted: it targeted the aurora-deferred-
                phase drift class (resolved 2026-06-16) and never generalized.
              */

              /**
                Routing table ↔ filesystem coherence. Body in
                lint/checks/routing-coherence.sh. Enforces that CLAUDE.md
                routes only to existing docs, every L2 doc is routed, and
                every L1 doc is both present + routed.
              */
              routing-coherence =
                pkgs.runCommandLocal "routing-coherence"
                  {
                    nativeBuildInputs = [
                      pkgs.bash
                      pkgs.gnugrep
                      pkgs.findutils
                      pkgs.coreutils
                    ];
                  }
                  ''
                    bash ${./lint/checks/routing-coherence.sh} ${./.}
                    touch $out
                  '';

              /**
                Every service module under modules/services/ must declare a
                backup intent — either `nori.backups.<name>.include = [...]`
                for what to back up, or `nori.backups.<name>.skip = "..."`
                for explicit opt-out. Forgetting to declare anything is the
                systemic cause of silent coverage gaps; this check turns
                forgetting into a build error.
              */
              every-service-has-backup-intent =
                pkgs.runCommandLocal "every-service-has-backup-intent"
                  {
                    nativeBuildInputs = [
                      pkgs.gnugrep
                      pkgs.findutils
                    ];
                  }
                  ''
                    cd ${./.}
                    fail=0

                    # Excluded paths — see baseNonServicePatterns at the
                    # top of `checks.${system}` for the shared list.
                    for f in $(find modules/services -name '*.nix' | sort); do
                      case "$f" in
                        ${mkCasePattern baseNonServicePatterns})
                          continue;;
                      esac
                      if ! grep -qE 'nori\.backups\.' "$f"; then
                        echo "✗ $f: no nori.backups.<name> declaration."
                        fail=1
                      fi
                    done

                    if [ $fail -eq 0 ]; then
                      touch $out
                    else
                      echo
                      echo "Every service module must declare a backup intent."
                      echo "Either:"
                      echo "  nori.backups.<name>.include = [ \"/var/lib/<svc>\" ];"
                      echo "or:"
                      echo "  nori.backups.<name>.skip = \"<one-line reason>\";"
                      echo
                      echo "See modules/infra/backup/default.nix for the schema."
                      exit 1
                    fi
                  '';

              /**
                Every service module under modules/services/ must declare a
                filesystem-hardening intent via `nori.harden.<name>`. Same
                silent-coverage-gap rationale as `every-service-has-backup-
                intent`: forgetting to harden a new service means it inherits
                only upstream's defaults, which often leaves /mnt and /home
                visible. This check turns forgetting into a build error.
              */
              every-service-has-fs-hardening =
                pkgs.runCommandLocal "every-service-has-fs-hardening"
                  {
                    nativeBuildInputs = [
                      pkgs.gnugrep
                      pkgs.findutils
                    ];
                  }
                  ''
                    cd ${./.}
                    fail=0

                    # Shared exclusions in baseNonServicePatterns at the top  # multi-line: ok (bash heredoc)
                    # of `checks.${system}`. Plus this check's specifics:
                    #   * ntfy/notify.nix — template only, no service of its own
                    #   * samba.nix       — legitimate /srv-full-access exception
                    for f in $(find modules/services -name '*.nix' | sort); do
                      case "$f" in
                        ${
                          mkCasePattern (
                            baseNonServicePatterns
                            ++ [
                              "modules/infra/observability/ntfy/notify.nix"
                              "modules/services/samba.nix"
                            ]
                          )
                        })
                          continue;;
                      esac
                      if ! grep -qE 'nori\.harden\.' "$f"; then
                        echo "✗ $f: no nori.harden.<name> declaration."
                        fail=1
                      fi
                    done

                    if [ $fail -eq 0 ]; then
                      touch $out
                    else
                      echo
                      echo "Every service module must declare a filesystem-hardening"
                      echo "intent via nori.harden.<service-name>. Default-deny baseline:"
                      echo "  ProtectHome=true, TemporaryFileSystem=[/mnt:ro,/srv:ro]"
                      echo "Set binds=[...] for writable paths, readOnlyBinds=[...] for"
                      echo "read-only, protectHome=null to leave upstream's value alone."
                      echo "See modules/infra/capabilities/default.nix for the schema."
                      exit 1
                    fi
                  '';

              /**
                Every `modules/infra/<X>/default.nix` that declares a
                Reader-shaped schema (options.nori.<name>) must ship a
                matching `test-<X>` runtime-introspection recipe in the
                Justfile. Codifies docs/reference/runtime-tests.md's
                "Four levers" framework: declaration at Reader level →
                generators at Writer level → runtime verification at
                test-* level. The convention prevents future infra
                additions from silently landing without their layer-3
                test (the failure mode that motivated audit findings
                #1 + #2 — silent harden/fs drift undetectable).

                Mapping registry. Each entry: directory name → expected
                Justfile recipe. Adding a new infra concern with Reader
                schema = adding one row OR the check fails.
              */
              infra-concerns-have-tests =
                let
                  expectedRecipes = {
                    backup = "test-backups";
                    capabilities = "test-harden";
                    networking = "test-routes";
                    observability = "test-observability";
                    storage = "test-fs";
                    access = "test-authelia";
                  };
                in
                pkgs.runCommandLocal "infra-concerns-have-tests"
                  {
                    nativeBuildInputs = [
                      pkgs.gnugrep
                      pkgs.findutils
                    ];
                  }
                  ''
                    cd ${./.}
                    fail=0

                    # Find Reader-shaped infra concerns (directories with a
                    # default.nix that declares options.nori.*).
                    concerns=$(
                      for f in $(find modules/infra -maxdepth 2 -name 'default.nix' | sort); do
                        if grep -qE 'options\.nori\.' "$f"; then
                          basename "$(dirname "$f")"
                        fi
                      done
                    )

                    # Walk the root Justfile + every co-located `*.just`
                    # fragment (recipes are co-located with the concern they
                    # operate on; see Justfile § "Co-location" for the map).
                    # `find` traverses the tree so fragments at any depth
                    # (modules/infra/<X>/<X>.just, tests/tests.just, …) get
                    # scanned without an explicit allowlist.
                    just_files="Justfile $(find . -name '*.just' -not -path './.git/*' -printf '%P\n' | sort | tr '\n' ' ')"

                    for concern in $concerns; do
                      case "$concern" in
                        ${lib.concatStringsSep "\n" (
                          lib.mapAttrsToList (dir: recipe: ''
                            ${dir})
                              if ! grep -qhE '^@?${recipe}:' $just_files; then
                                echo "✗ modules/infra/${dir}/ → expected '${recipe}' recipe (not in: $just_files)"
                                fail=1
                              fi
                              ;;
                          '') expectedRecipes
                        )}
                        *)
                          echo "✗ modules/infra/$concern/ declares options.nori.* but has no entry in expectedRecipes"
                          echo "    Add to flake.nix § checks.infra-concerns-have-tests with the recipe name"
                          echo "    that covers it, and ship the recipe in the Justfile or an imported *.just."
                          fail=1
                          ;;
                      esac
                    done

                    if [ $fail -eq 0 ]; then
                      touch $out
                    else
                      echo
                      echo "Every Reader-shaped infra concern needs a runtime-introspection recipe."
                      echo "See docs/reference/runtime-tests.md § 'Four levers' for the framework."
                      echo "Promotion register: docs/invariants.md § infra-concerns-have-tests."
                      exit 1
                    fi
                  '';

              /**
                E2E — pi-alone smoke nixosTest. Boots a stripped-down
                pi-like config in QEMU + verifies the homelab services
                reach active state. The per-service scope (Phase 1
                through Phase 5+) is documented in
                docs/specs/2026-06-17-e2e-vm-simulation.md. Per
                docs/reference/testing-methodology.md this is layer 2
                (nixosTest) — pair with layer-1 eval tests at
                tests/eval/ for sub-second feedback during inner-loop
                iteration.
              */
              e2e-pi-smoke = import ./tests/e2e-pi-smoke.nix { inherit pkgs lib inputs; };
              e2e-multi-host = import ./tests/e2e-multi-host.nix { inherit pkgs lib inputs; };
              e2e-restic-backup = import ./tests/e2e-restic-backup.nix { inherit pkgs lib inputs; };
              e2e-disk-alert = import ./tests/e2e-disk-alert.nix { inherit pkgs lib inputs; };

              /**
                Layer-1 eval test — `nori.lanRoutes` → blocky.customDNS
                auto-generation. Sub-second; runs at every flake check
                via the import below. Per docs/reference/testing-
                methodology.md: eval tests catch schema regressions +
                cross-module composition errors before they surface in
                the nixosTest (which is much slower).
              */
              eval-lanroute-customdns =
                let
                  result = import ./tests/eval/lanroute-customdns.nix {
                    inherit pkgs lib inputs;
                  };
                in
                pkgs.runCommandLocal "eval-lanroute-customdns" { } ''
                  echo ${lib.escapeShellArg result} > $out
                '';

              /**
                Layer-1 eval test — `nori.lanRoutes.<X>.port` validates as
                16-bit unsigned (types.port). Demonstrates the
                negative-path eval pattern: assert that a BAD config
                throws, not just that a good config succeeds.
              */
              eval-lanroute-port-validation =
                let
                  result = import ./tests/eval/lanroute-port-validation.nix {
                    inherit pkgs lib inputs;
                  };
                in
                pkgs.runCommandLocal "eval-lanroute-port-validation" { } ''
                  echo ${lib.escapeShellArg result} > $out
                '';

              /**
                Layer-1 eval test — cross-product invariants over
                nori.lanRoutes. Verifies module assertions in
                modules/infra/networking/default.nix actually FIRE on
                the failure modes (port collisions, runsOn ∉ nori.hosts).
                Catches regressions that drop an assertion silently.
              */
              eval-route-invariants =
                let
                  result = import ./tests/eval/route-invariants.nix {
                    inherit pkgs lib inputs;
                  };
                in
                pkgs.runCommandLocal "eval-route-invariants" { } ''
                  echo ${lib.escapeShellArg result} > $out
                '';

              /**
                Layer-1 eval test — `nori.lanRoutes.<X>.monitor` →
                `services.gatus.settings.endpoints`. Pins the registry-
                to-Gatus contract so a schema regression that silently
                drops endpoints (and the operator's alerting) fails the
                check.
              */
              eval-gatus-probes =
                let
                  result = import ./tests/eval/gatus-probes.nix {
                    inherit pkgs lib inputs;
                  };
                in
                pkgs.runCommandLocal "eval-gatus-probes" { } ''
                  echo ${lib.escapeShellArg result} > $out
                '';

              /**
                Docs-fresh — committed generated artifacts must match
                what the generators would produce right now. Catches the
                drift class where a schema change lands but the docs/
                reference/*.md artifact isn't regenerated + committed.
                Each diff is byte-equal; a single byte difference fails
                the build with the diff inline.
              */
              docs-fresh =
                pkgs.runCommandLocal "docs-fresh"
                  {
                    nativeBuildInputs = [ pkgs.diffutils ];
                  }
                  ''
                    fail=0
                    check() {
                      local name=$1 committed=$2 generated=$3
                      if ! diff -q "$committed" "$generated" > /dev/null 2>&1; then
                        echo "✗ $name: committed artifact differs from generator output"
                        echo "  committed:  $committed"
                        echo "  generator:  $generated"
                        echo "  diff:"
                        diff "$committed" "$generated" | head -20 | sed 's/^/    /'
                        fail=1
                      fi
                    }
                    check "docs-lan-route" \
                      ${./docs/generated/lan-route.md} \
                      ${inputs.self.packages.${system}.docs-lan-route}
                    check "docs-topology" \
                      ${./docs/generated/topology.md} \
                      ${inputs.self.packages.${system}.docs-topology}
                    check "docs-capabilities" \
                      ${./docs/generated/capabilities.md} \
                      ${inputs.self.packages.${system}.docs-capabilities}
                    check "docs-backups" \
                      ${./docs/generated/backups.md} \
                      ${inputs.self.packages.${system}.docs-backups}
                    check "docs-fs" \
                      ${./docs/generated/fs.md} \
                      ${inputs.self.packages.${system}.docs-fs}
                    check "docs-replicas" \
                      ${./docs/generated/replicas.md} \
                      ${inputs.self.packages.${system}.docs-replicas}

                    if [ $fail -eq 0 ]; then
                      touch $out
                    else
                      echo
                      echo "Generated docs drifted. Regenerate + commit any failures:"
                      for name in lan-route topology capabilities backups fs replicas; do
                        echo "  nix build .#docs-$name -o /tmp/r && cp /tmp/r docs/generated/$name.md && chmod +w docs/generated/$name.md"
                      done
                      exit 1
                    fi
                  '';

            };
        };
    };
}
