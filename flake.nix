{
  description = "nori infrastructure (NixOS) — workstation and future lab hosts";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    /*
      nixpkgs master — used ONLY for cherry-picking individual packages
      whose nixos-unstable channel cut lags far behind upstream. Don't
      mass-overlay from this; resolve specific lags one package at a
      time. Currently consumed by:
        modules/desktop/apps.nix → zed-editor (nixos-unstable shipping
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
      via modules/desktop/stylix.nix.
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
      nix-community/impermanence — "erase your darlings" mechanism.
      Opt-in per host. Consumed by machines/pavilion (agent quarantine):
      pavilion uses btrfs-rollback rather than tmpfs root (3.6 GB RAM
      ceiling) — the impermanence module is FS-agnostic; the rollback
      service in pavilion's default.nix provides the clean state on disk.
    */
    impermanence.url = "github:nix-community/impermanence";

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
    {
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;

      /*
        `system` here is the host on which `nix flake check` /
        formatter / etc run — not the target platform of any host.
        Each host's hardware.nix sets nixpkgs.hostPlatform; mkHost
        no longer hardcodes system, so pi (aarch64-linux) and
        workstation (x86_64-linux) coexist cleanly.
      */
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      /*
        A second pkgs binding with `allowUnfree = true` for the dev
        shell — needed because `claude-code` is unfree and the
        default `legacyPackages.${system}` honours the strict
        default. Hosts get unfree separately via
        `modules/common/base.nix` setting `nixpkgs.config.allowUnfree`,
        but that path doesn't reach flake-level outputs like devShells.
      */
      pkgsUnfree = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

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
    {
      inherit (machinesModule) nixosConfigurations;

      /*
        Minimal dev shell for editing this repo. Dev environments are
        a per-project concern (devenv / direnv / nix shell), not a
        homelab-managed capability — each repo owns its own dev
        config. This shell gives `nix develop` here the tools needed
        to edit + format + lint the homelab itself.
      */
      devShells.${system}.default = pkgsUnfree.mkShell {
        buildInputs = with pkgsUnfree; [
          nixfmt
          statix
          deadnix
          nh
          ripgrep
        ];
      };

      # Standalone home-manager configurations come from
      # modules/home/default.nix.
      inherit (homeModule) homeConfigurations;

      formatter.${system} = pkgs.nixfmt;

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
      packages.${system} =
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
                nixdoc --description ${lib.escapeShellArg description} \
                       --prefix ${lib.escapeShellArg prefix} \
                       --category ${lib.escapeShellArg category} \
                       --file ${file} > $out
              '';
        in
        {
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
                store path's hash differs each rebuild).
              */
              stripStorePrefix =
                p:
                let
                  s = toString p;
                  pattern = "/nix/store/[^/]*-source/";
                in
                if lib.hasPrefix "/nix/store/" s then
                  let
                    m = builtins.match "/nix/store/[^/]*-source/(.*)" s;
                  in
                  if m == null then s else "${pattern}" + builtins.head m
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
            pkgs.runCommandLocal "docs-lan-route" { } ''
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
              cat ${optionsDoc.optionsCommonMark} >> $out
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
                  pattern = "/nix/store/[^/]*-source/";
                in
                if lib.hasPrefix "/nix/store/" s then
                  let
                    m = builtins.match "/nix/store/[^/]*-source/(.*)" s;
                  in
                  if m == null then s else "${pattern}" + builtins.head m
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
            in
            pkgs.runCommandLocal "docs-topology" { } ''
              cat > $out <<'HEADER'
              ---
              generated: true
              source: flake.nix § packages.docs-topology
              regenerate: nix build .#docs-topology
              ---

              # Topology — generated reference

              Auto-derived from `nori.hosts` schema + `identityFor` values
              in `modules/machines/default.nix`. Do not hand-edit; the
              hand-curated overview + diagram + invariants live in
              `docs/reference/topology.md`.

              ## Hosts at a glance

              HEADER
              cat >> $out <<'TABLE'
              ${hostsTable}
              TABLE
              cat >> $out <<'SCHEMA_HEADER'

              ## Registry schema (`nori.hosts.<name>.*`)

              What an `identityFor` entry must declare to satisfy the schema.
              Schema lives in `modules/infra/hosts.nix`; values live in
              `modules/machines/default.nix`.

              SCHEMA_HEADER
              cat ${optionsDoc.optionsCommonMark} >> $out
            '';

        };

      # Quality gates. `nix flake check` validates host evals + the
      # checks below; `nix flake show .#checks` is the live index.
      checks.${system} =
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
            cd ${./.}
            ${pkgs.nixfmt}/bin/nixfmt --check $(find . -name '*.nix' -not -path '*/result/*')
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
                  ${./docs/reference/lan-route-options.md} \
                  ${inputs.self.packages.${system}.docs-lan-route}
                check "docs-topology" \
                  ${./docs/reference/topology-generated.md} \
                  ${inputs.self.packages.${system}.docs-topology}

                if [ $fail -eq 0 ]; then
                  touch $out
                else
                  echo
                  echo "Generated docs drifted. Regenerate + commit:"
                  echo "  nix build .#docs-lan-route -o /tmp/r && \\"
                  echo "    cp /tmp/r docs/reference/lan-route-options.md"
                  echo "  nix build .#docs-topology  -o /tmp/r && \\"
                  echo "    cp /tmp/r docs/reference/topology-generated.md"
                  echo "  chmod +w docs/reference/{lan-route-options,topology-generated}.md"
                  exit 1
                fi
              '';

        };
    };
}
