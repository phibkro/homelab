{
  description = "nori infrastructure (NixOS) — workstation and future lab hosts";

  # Pinned to stable nixos-26.05 (shipped 2026-06). Moved off unstable
  # after a cascade of mismatched-version pain (Stylix moved ahead of
  # home-manager → `configType` errors, hyprland 0.55 hyprlang
  # deprecation, electron-39 EOL etc.). Trade-off accepted: no more
  # 0-day packages, but Stylix/home-manager match by version label
  # (warnings gone) and rebuilds follow predictable stable-line churn.
  # Re-pin to a newer stable deliberately on `nix flake update`.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # nixpkgs master — used ONLY for cherry-picking individual packages
    # whose nixos-unstable channel cut lags far behind upstream. Don't
    # mass-overlay from this; resolve specific lags one package at a
    # time. Currently consumed by:
    #   modules/desktop/apps.nix → zed-editor (nixos-unstable shipping
    #     v0.232.3 as of 2026-05-07, master shipping v1.1.6; months of
    #     Linux/Wayland/file-watcher fixes in the gap)
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Per-user config (desktop phase). Pinned to release-26.05 to match
    # nixpkgs. Mac homeConfiguration rides this too — 26.05 was
    # announced as the LAST nixpkgs release supporting Intel Mac
    # (x86_64-darwin), so this pin is the natural Mac end-of-line:
    # either keep 26.05 indefinitely or migrate Mac off nixpkgs.
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Zen browser. Not in nixpkgs; consumed via upstream community flake.
    # `.default` tracks rolling Twilight; pivot to `.beta` or `.specific`
    # if Twilight churn becomes annoying.
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";

    # snappy-switcher — Hyprland-native alt-tab overlay (pure C, Wayland
    # layer shell, no GTK/Electron). Not in nixpkgs; upstream ships a
    # flake. ALT+Tab (MRU global) + SUPER+Tab (workspace-local) bound
    # in machines/workstation/hyprland.lua; daemon autostarted there too.
    snappy-switcher.url = "github:OpalAayan/snappy-switcher";
    snappy-switcher.inputs.nixpkgs.follows = "nixpkgs";

    # hermes-agent — NousResearch's open-source self-improving coding agent
    # with persistent memory (SQLite session DB + MEMORY.md + pluggable
    # provider plugins). Not in nixpkgs; upstream ships an official flake
    # using uv2nix. We consume `packages.default` (bare CLI) for
    # interactive use inside `box`. The `messaging` / `full` variants are
    # available if we ever want Discord/Telegram or external memory
    # providers like Honcho/Mem0.
    #
    # No GitHub credential is plumbed into hermes by design — see the
    # security note in modules/claude-code/default.nix; operator-driven
    # claude-code remains the only path to commit/push.
    hermes-agent.url = "github:NousResearch/hermes-agent";
    hermes-agent.inputs.nixpkgs.follows = "nixpkgs";

    # ollama package overlaid from nixpkgs `release-26.05` (which
    # carries 0.30.5 via backport of #527892 + #528150). The main
    # `nixpkgs` input above tracks the `nixos-26.05` channel, which
    # currently lags behind release-26.05 on ollama. Drop this input
    # + the `services.ollama.package` override in
    # modules/server/ollama.nix when the channel catches up.
    nixpkgs-ollama.url = "github:NixOS/nixpkgs/release-26.05";

    # Stylix — single-input system-wide theming. One wallpaper +
    # polarity (light/dark) generates a Material You-flavored base16
    # palette and applies it to GTK, Qt, Hyprland, Kitty, btop, etc.
    # Same Reader+collected-Writer shape as the rest of the lab's
    # effect family — fits cleanly. Workstation imports the NixOS
    # module via modules/desktop/stylix.nix.
    stylix.url = "github:danth/stylix/release-26.05";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    # Third-party Claude Code skill sources — pinned via flake.lock,
    # consumed as plain source trees by modules/claude-code/default.nix.
    # Update via `nix flake update --update-input <name>`. Not flakes
    # themselves, hence flake = false.
    superpowers.url = "github:obra/superpowers";
    superpowers.flake = false;
    caveman.url = "github:juliusbrussee/caveman";
    caveman.flake = false;
    # Anthropics' public Agent-Skills repo. We only consume the
    # frontend-design subdir today; the rest (xlsx, pptx, mcp-builder,
    # etc.) is one extra symlink away if/when needed.
    anthropics-skills.url = "github:anthropics/skills";
    anthropics-skills.flake = false;
    # masonjames/Shadcnblocks-Skill — gives Claude Code expert
    # knowledge of 2,500+ shadcn/ui blocks. Single `shadcn-ui` skill.
    shadcn.url = "github:masonjames/Shadcnblocks-Skill";
    shadcn.flake = false;
    # kepano/obsidian-skills — multi-skill (defuddle, json-canvas,
    # obsidian-bases, obsidian-cli, obsidian-markdown). We only
    # consume obsidian-markdown today.
    obsidian-skills.url = "github:kepano/obsidian-skills";
    obsidian-skills.flake = false;

    # nix-community/impermanence — "erase your darlings" mechanism.
    # Consumed by machines/pavilion (the agent quarantine host) so
    # every boot starts from a clean state and only declared paths
    # under /persist survive. Pavilion uses btrfs-rollback rather
    # than tmpfs root (3.6 GB RAM ceiling) — the impermanence module
    # is FS-agnostic; the rollback service in pavilion's default.nix
    # is what provides the clean state on disk. Workstation, pi, and
    # macbook all keep mutable roots; impermanence is opt-in per host.
    impermanence.url = "github:nix-community/impermanence";

    # pagu-box — cross-platform sandboxed launcher for any process.
    # Pinned to the LOCAL checkout (path:) rather than github so the
    # homelab picks up uncommitted operator edits without a push +
    # `flake update` cycle each iteration. pagu-box is operator-owned
    # and lives alongside the homelab; pinning local matches the dev
    # model. Flip to `github:phibkro/pagu-box` if someone else needs
    # to consume this flake on a machine without that checkout.
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

      # `system` here is the host on which `nix flake check` /
      # formatter / etc run — not the target platform of any host.
      # Each host's hardware.nix sets nixpkgs.hostPlatform; mkHost
      # no longer hardcodes system, so pi (aarch64-linux) and
      # workstation (x86_64-linux) coexist cleanly.
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # A second pkgs binding with `allowUnfree = true` for the dev
      # shell — needed because `claude-code` is unfree and the
      # default `legacyPackages.${system}` honours the strict
      # default. Hosts get unfree separately via
      # `modules/common/base.nix` setting `nixpkgs.config.allowUnfree`,
      # but that path doesn't reach flake-level outputs like devShells.
      pkgsUnfree = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # ── Machines ──────────────────────────────────────────────────
      # The list of machines is the filesystem: each subdirectory of
      # ./machines/ is a machine. NixOS hosts have a default.nix;
      # standalone home-manager machines (like Mac) have only a
      # home.nix. The flake derives both shapes from the directory.
      #
      # Identity metadata (tailnet/lan IPs, role) is indexed by NixOS
      # host name in `identityFor` below — non-NixOS machines aren't in
      # the registry because nothing in the NixOS module system
      # references them. The genAttrs lookup forces every NixOS host
      # folder to have an identity entry — a folder without identity
      # fails eval; an identity entry without a folder is silently dead
      # code (caught by code review, visible at deploy time).
      #
      # Schema: modules/effects/hosts.nix.
      # Consumers (cross-host refs):
      #   * modules/effects/lan-route.nix       (nori.lanIp default)
      #   * modules/effects/backup.nix          (host-aware appliance assertion)
      #   * modules/server/beszel/agent.nix     (metrics route backend)
      #   * modules/server/ntfy/notify.nix      (alert route backend)
      #   * machines/workstation/default.nix    (Pi probe URLs)
      #
      # Topology change = edit identityFor, redeploy. Adding a NixOS
      # host = `mkdir machines/<n> && touch machines/<n>/{default,hardware}.nix`
      # plus an identityFor entry — eval errors on either omission.
      # Adding a non-NixOS machine = `mkdir machines/<n> && touch
      # machines/<n>/home.nix` (no default.nix; not in identityFor).
      machineNames = lib.attrNames (
        lib.filterAttrs (_: t: t == "directory") (builtins.readDir ./machines)
      );

      # NixOS machines are those with a default.nix. Drives both
      # nixosConfigurations enumeration and the host registry.
      nixosMachineNames = lib.filter (
        n: builtins.pathExists (./machines + "/${n}/default.nix")
      ) machineNames;

      identityFor = {
        workstation = {
          tailnetIp = "100.81.5.122";
          lanIp = "192.168.1.181";
          role = "workhorse";
        };
        pi = {
          tailnetIp = "100.100.71.3";
          lanIp = "192.168.1.225";
          role = "appliance";
        };
        # Pavilion — HP g6 retasked as the agent quarantine host.
        # Tailnet IP fills in after first `tailscale up`; lan stays
        # null since the device roams (no static DHCP reservation).
        # See machines/pavilion/default.nix for the impermanence /
        # agent-role posture. Sits under tag:agent in the Tailscale ACL
        # — can reach workhorse :11434 (ollama) only; cannot SSH any
        # privileged-tier host.
        pavilion = {
          tailnetIp = "100.93.230.66";
          lanIp = null; # roams; no static DHCP lease
          role = "agent";
        };
      };

      hostRegistry = lib.genAttrs nixosMachineNames (n: identityFor.${n});

      # ── Dev shells ────────────────────────────────────────────────
      # Per-project dev environments composed from atomic fragments
      # under modules/dev/. Each fragment contributes buildInputs +
      # Claude allowlists + shell hooks; the composer (`mkDevShell`)
      # resolves transitive deps + merges + returns a `pkgs.mkShell`.
      # See modules/dev/default.nix for the composer; modules/dev/
      # *.nix for the fragment library. Exposed via `self.lib` so
      # downstream project flakes can `inputs.lab.url = "..."` then
      # call `lab.lib.mkDevShell pkgs { modules = [ ... ]; }`.
      devLib = import ./modules/dev { inherit lib; };

      mkHost =
        name:
        lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./machines/${name}
            # Inject from the registry: hostName comes from the same
            # name that picks the host folder. The folder name is the
            # source of truth — registry keys derive from readDir,
            # networking.hostName injects from the same name. No
            # parallel string to keep in sync.
            #
            # Every host sees the full registry so cross-host
            # references (config.nori.hosts.<other>.tailnetIp) resolve.
            {
              config.networking.hostName = name;
              config.nori.hosts = hostRegistry;
            }
          ];
        };
    in
    {
      nixosConfigurations = lib.genAttrs nixosMachineNames mkHost;

      # Dev-shell composer + the available fragment list. Consumers
      # (downstream project flakes, this flake's own devShells) call
      # `mkDevShell pkgs { modules = [ "ts" "claude-code" ]; }` to get
      # a configured `pkgs.mkShell`. `fragmentNames` is the live list
      # — read it via `nix eval .#lib.fragmentNames` rather than
      # maintaining a static doc table.
      lib = {
        inherit (devLib) mkDevShell fragmentNames;
      };

      # Self-test: this repo's own dev shell. `nix develop` here gives
      # nixfmt + statix + deadnix + nh + claude-code, plus a
      # materialized `.claude/settings.json` whose allowlist is the
      # union of nix + claude-code fragment contributions. The
      # operator-specific settings.local.json layers on top.
      devShells.${system}.default = devLib.mkDevShell pkgsUnfree {
        modules = [
          "nix"
          "claude-code"
        ];
      };

      # Standalone home-manager configurations for non-NixOS machines.
      # Activated on the target machine via:
      #   nix run home-manager/master -- switch --flake .#<name>
      # or, once home-manager is installed into the user profile:
      #   home-manager switch --flake .#<name>
      #
      # NixOS machines embed home-manager as a NixOS module inside their
      # own machines/<n>/default.nix; these standalone entries are only
      # for machines where the host OS isn't NixOS (Mac).
      homeConfigurations.macbook = home-manager.lib.homeManagerConfiguration {
        # Mac pkgs with allowUnfree so claude-code (unfree license)
        # resolves. Same pattern as `pkgsUnfree` above for the dev shell.
        pkgs = import nixpkgs {
          system = "x86_64-darwin";
          config.allowUnfree = true;
        };
        # Pass `inputs` to home-manager modules so modules/claude-code/
        # can reach the third-party-skill flake inputs (superpowers,
        # caveman, anthropics-skills). Workstation gets the same via
        # extraSpecialArgs in its NixOS-side home-manager wrapper.
        extraSpecialArgs = { inherit inputs; };
        modules = [ ./machines/macbook/home.nix ];
      };

      formatter.${system} = pkgs.nixfmt;

      # Quality gates. Run `nix flake check` to validate everything:
      #   - host configs evaluate (catches type errors, missing
      #     options, and any module assertion violations)
      #   - statix flags Nix anti-patterns
      #   - deadnix flags unused bindings
      #   - format-check fails on unformatted .nix files
      #   - forbidden-patterns catches grepable repo-conventions
      #     (no inline OIDC hashes, no direct caddy/blocky bypass)
      checks.${system} =
        let
          # Files under modules/server/ that aren't user-facing services —
          # folder aggregators, the *arr group's `media`-bootstrap helper,
          # and the backup-cluster framework. Both `every-service-has-<X>`
          # checks share this baseline; per-check additions (e.g. samba's
          # /srv exception, notify@'s template-only file) are appended
          # below at the call site.
          baseNonServicePatterns = [
            "*/default.nix"
            "modules/server/arr/shared.nix"
            "modules/server/backup/restic.nix"
            "modules/server/backup/verify.nix"
            "modules/server/backup/btrbk.nix"
          ];
          # Generate a `case` glob from a list of patterns, joined with
          # `|`. Used at the head of each scanner loop to skip framework
          # / aggregator files.
          mkCasePattern = ps: lib.concatStringsSep "|" ps;
        in
        {
          # cd into the source so statix picks up `statix.toml` (looked up
          # from the working directory, not the path argument).
          statix = pkgs.runCommandLocal "statix" { } ''
            cd ${./.}
            ${pkgs.statix}/bin/statix check . > $out
          '';

          # --no-lambda-pattern-names: NixOS module convention is to
          # declare `{ config, lib, pkgs, ... }:` even when not all are
          # used; tolerate that. Still flags genuine unused
          # let-bindings and other dead code.
          deadnix = pkgs.runCommandLocal "deadnix" { } ''
            ${pkgs.deadnix}/bin/deadnix --fail --no-lambda-pattern-names ${./.}
            touch $out
          '';

          format = pkgs.runCommandLocal "format" { } ''
            cd ${./.}
            ${pkgs.nixfmt}/bin/nixfmt --check $(find . -name '*.nix' -not -path '*/result/*')
            touch $out
          '';

          # Repo-convention enforcement. Each rule below is a hard
          # constraint, not a suggestion: the convention is whatever the
          # check enforces. Adding a deliberate exception means editing
          # this rule, not just bypassing it. Patterns are `grep -rn`
          # and intentionally simple — anything that needs AST-aware
          # checking should graduate to a tree-sitter-nix wrapper.
          forbidden-patterns =
            pkgs.runCommandLocal "forbidden-patterns"
              {
                nativeBuildInputs = [ pkgs.gnugrep ];
              }
              ''
                cd ${./.}
                fail=0

                # No inline PBKDF2 client_secret hashes anywhere in modules.
                # OIDC client hashes live only in sops as
                # oidc-<n>-client-secret-hash; Authelia reads them via the
                # template config-filter (see modules/services/authelia.nix).
                if grep -rn '\$pbkdf2-' modules/ ; then
                  echo
                  echo "✗ Inline pbkdf2 hashes found above. OIDC hashes belong in sops"
                  echo "  (key: oidc-<n>-client-secret-hash). See"
                  echo "  .claude/skills/add-oidc-client/ for the bootstrap workflow."
                  fail=1
                fi

                # The `clientSecretHash` field was removed from the lanRoutes
                # oidc submodule when the template-filter migration landed —
                # any reference is stale.
                if grep -rn 'clientSecretHash' modules/ ; then
                  echo
                  echo "✗ clientSecretHash field references found. The field was"
                  echo "  removed; hashes live in sops as oidc-<n>-client-secret-hash."
                  fail=1
                fi

                # Caddy vhost declarations must come from
                # modules/effects/lan-route.nix only — nori.lanRoutes is the
                # single source of truth for *.nori.lan exposure.
                if grep -rln 'services\.caddy\.virtualHosts' modules/ \
                   | grep -v '^modules/effects/lan-route\.nix$' ; then
                  echo
                  echo "✗ Direct services.caddy.virtualHosts found above. Use"
                  echo "  nori.lanRoutes.<name> = { port = N; }; instead — the"
                  echo "  abstraction generates Caddy + Blocky + Gatus together."
                  fail=1
                fi

                # Blocky customDNS mappings — same single-source rule.
                if grep -rln 'services\.blocky\.settings\.customDNS' modules/ \
                   | grep -v '^modules/effects/lan-route\.nix$' ; then
                  echo
                  echo "✗ Direct services.blocky.settings.customDNS found above."
                  echo "  Use nori.lanRoutes.<name> instead."
                  fail=1
                fi

                # Caddy's internal CA is enabled via globalConfig =
                # "local_certs", not via acmeCA = "internal" — Caddy will
                # literally try to dial `internal` as an ACME directory URL
                # and fail. See .claude/skills/gotcha-caddy-acme-internal/
                if grep -rn 'acmeCA = "internal"' modules/ ; then
                  echo
                  echo "✗ acmeCA = \"internal\" found above. Caddy interprets this"
                  echo "  as a literal ACME directory URL. Use:"
                  echo '    services.caddy.globalConfig = "local_certs";'
                  fail=1
                fi

                # Gatus's ntfy alerting provider takes `url` and `topic` as
                # SEPARATE fields. Embedding the topic in the URL silently
                # disables alerting (logs "Ignoring provider=ntfy due to
                # error=topic not set" once at startup, then nothing).
                # See .claude/skills/gotcha-gatus-ntfy-provider/
                if grep -rn 'url = "https://ntfy.sh/' modules/ ; then
                  echo
                  echo "✗ Gatus ntfy URL with embedded topic found above. Split into"
                  echo "  separate fields:"
                  echo '    alerting.ntfy.url   = "https://ntfy.sh";'
                  echo "    alerting.ntfy.topic = \"\''${NTFY_CHANNEL}\";"
                  fail=1
                fi

                # Tailnet IP literals (CGNAT 100.64.0.0/10) outside flake.nix's
                # identityFor are stale before the next topology change. Cross-
                # host references go through the topology registry:
                # `config.nori.hosts.<host>.tailnetIp`. flake.nix is the only
                # legitimate site for the host-specific literal.
                #
                # Allowlist:
                #   * 100.100.100.100  Tailscale MagicDNS stub (well-known
                #                      constant, not a host)
                #   * 100.64.0.0/10    CGNAT range (network spec, not a host —
                #                      legitimate in firewall ACLs)
                #   * modules/effects/hosts.nix  registry schema's own header
                #                                comment narrates the refactor
                if grep -rEn '\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+\b' \
                     modules/ hosts/ \
                   | grep -vE '100\.100\.100\.100|100\.64\.0\.0/10' \
                   | grep -v '^modules/effects/hosts\.nix:' ; then
                  echo
                  echo "✗ Tailnet IP literal (CGNAT range) found above. Use"
                  echo "  config.nori.hosts.<host>.tailnetIp from the topology"
                  echo "  registry. Schema: modules/effects/hosts.nix; values:"
                  echo "  flake.nix identityFor."
                  fail=1
                fi

                if [ $fail -eq 0 ]; then
                  touch $out
                else
                  exit 1
                fi
              '';

          # Doc-code coherence. Catches the specific drift class where
          # a host (or other named module) is live in the repo, but a
          # doc still calls it deferred / planned / not-yet-done.
          #
          # The rule: for each host actually declared under machines/,
          # no markdown line in docs/ or at the repo root may mention
          # both `machines/<host>/` AND a "deferred"-class word. If the
          # host folder is present, it's live; saying otherwise in prose
          # is stale.
          #
          # This is intentionally narrow — it requires the path
          # reference, not just the bare host name — so the word
          # "deferred" remains usable for legitimate non-host topics
          # (Hetzner deferred, email digest deferred, etc.).
          doc-coherence =
            pkgs.runCommandLocal "doc-coherence"
              {
                nativeBuildInputs = [
                  pkgs.gnugrep
                  pkgs.findutils
                ];
              }
              ''
                cd ${./.}
                fail=0

                hosts=$(find machines -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)
                docs=$(find docs -name '*.md'; ls README.md 2>/dev/null)

                for h in $hosts; do
                  # Lines that mention machines/<host>/ AND a deferred-class
                  # word, in either order. -i for case (DEFERRED is common).
                  if grep -inE \
                       "(machines/''${h}[/ ].*\b(deferred|planned|pending|tbd)\b)|(\b(deferred|planned|pending|tbd)\b.*machines/''${h}[/ ])" \
                       $docs ; then
                    echo
                    echo "✗ host ''${h} is live in machines/''${h}/ but docs above"
                    echo "  call it deferred/planned/pending. Either remove the"
                    echo "  stale line or remove the host folder."
                    fail=1
                  fi
                done

                if [ $fail -eq 0 ]; then
                  touch $out
                else
                  exit 1
                fi
              '';

          # Every service module under modules/server/ must declare a
          # backup intent — either `nori.backups.<name>.include = [...]`
          # for what to back up, or `nori.backups.<name>.skip = "..."`
          # for explicit opt-out. Forgetting to declare anything is the
          # systemic cause of silent coverage gaps; this check turns
          # forgetting into a build error.
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
                for f in $(find modules/server -name '*.nix' | sort); do
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
                  echo "See modules/effects/backup.nix for the schema."
                  exit 1
                fi
              '';

          # Every service module under modules/server/ must declare a
          # filesystem-hardening intent via `nori.harden.<name>`. Same
          # silent-coverage-gap rationale as `every-service-has-backup-
          # intent`: forgetting to harden a new service means it inherits
          # only upstream's defaults, which often leaves /mnt and /home
          # visible. This check turns forgetting into a build error.
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

                # Shared exclusions in baseNonServicePatterns at the top
                # of `checks.${system}`. Plus this check's specifics:
                #   * ntfy/notify.nix — template only, no service of its own
                #   * samba.nix       — legitimate /srv-full-access exception
                for f in $(find modules/server -name '*.nix' | sort); do
                  case "$f" in
                    ${
                      mkCasePattern (
                        baseNonServicePatterns
                        ++ [
                          "modules/server/ntfy/notify.nix"
                          "modules/server/samba.nix"
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
                  echo "See modules/effects/harden.nix for the schema."
                  exit 1
                fi
              '';

        };
    };
}
