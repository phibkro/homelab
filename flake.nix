{
  description = "nori infrastructure (NixOS) — workstation and future lab hosts";

  # Pinned to nixos-unstable because workstation has an RTX 5060 Ti
  # (Blackwell), whose driver lands in recent nixpkgs. Treat unstable +
  # flake.lock as the de-facto stable channel; re-pin deliberately.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Per-user config (desktop phase). Tracks nixos-unstable in lockstep
    # with nixpkgs; re-pin deliberately on `nix flake update`.
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Zen browser. Not in nixpkgs; consumed via upstream community flake.
    # `.default` tracks rolling Twilight; pivot to `.beta` or `.specific`
    # if Twilight churn becomes annoying.
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      disko,
      sops-nix,
      home-manager,
      zen-browser,
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

      # ── Hosts ─────────────────────────────────────────────────────
      # The list of hosts is the filesystem: each subdirectory of
      # ./hosts/ is a host. readDir + filterAttrs gets us the names
      # without a parallel registry to drift out of sync.
      #
      # Identity metadata (tailnet/lan IPs, role) is indexed by host
      # name in `identityFor` below. The genAttrs lookup forces every
      # folder to have an identity entry — a folder without identity
      # fails eval ("attribute missing"); an identity entry without a
      # folder is silently dead code (caught by code review, but the
      # absence of effect is visible at deploy time).
      #
      # Schema: modules/effects/hosts.nix.
      # Consumers (cross-host refs):
      #   * modules/effects/lan-route.nix       (nori.lanIp default)
      #   * modules/effects/backup.nix          (host-aware appliance assertion)
      #   * modules/server/beszel/agent.nix (metrics route backend)
      #   * modules/server/ntfy/notify.nix  (alert route backend)
      #   * hosts/workstation/default.nix  (Pi probe URLs)
      #
      # Topology change = edit identityFor, redeploy. Adding a host =
      # `mkdir hosts/<n> && touch hosts/<n>/{default,hardware}.nix`
      # plus an identityFor entry — eval errors on either omission.
      hostNames = lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir ./hosts));

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
      };

      hostRegistry = lib.genAttrs hostNames (n: identityFor.${n});

      mkHost =
        name:
        lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/${name}
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
      nixosConfigurations = lib.genAttrs hostNames mkHost;

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
                  echo "  (key: oidc-<n>-client-secret-hash). See docs/CONVENTIONS.md"
                  echo "  'Authelia OIDC pattern'."
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
                # and fail. See docs/gotchas.md "Caddy: acmeCA = internal
                # is wrong".
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
                # See docs/gotchas.md "Gatus ntfy provider".
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

          # Every service module under modules/server/ must declare a
          # backup intent — either `nori.backups.<name>.paths = [...]`
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
                  echo "  nori.backups.<name>.paths = [ \"/var/lib/<svc>\" ];"
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
