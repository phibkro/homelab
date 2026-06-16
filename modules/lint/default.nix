# nori.lint — declarative grep-rule registry + lowering to a single
# `nix flake check` derivation. Shares the Reader+Writer data shape
# with the `nori.<X>` effect family in modules/effects/, but lives
# outside that folder because lint is dev-time tooling — affects
# `nix flake check`, not running system state.
#
# Mechanism note: unlike nori.lanRoutes / nori.backups / nori.harden,
# which collect entries via the NixOS module system from MULTIPLE
# service modules (fan-in), nori.lint's rules all live in one place
# (./rules.toml, consumed by flake.nix). The NixOS module collection
# mechanism would pay eval cost for zero benefit, so this exports a
# plain Nix function instead of registering an `options.nori.lint`
# attribute. The Reader+Writer pattern earns its keep when there's
# fan-in to collect; here we just have one Reader and one Writer.
#
# Usage (in flake.nix's `checks.${system}` let-block):
#
#   let
#     lintLib = import ./modules/lint { inherit lib pkgs; };
#   in {
#     lint = lintLib.makeLintCheck {
#       rules = (builtins.fromTOML (builtins.readFile ./modules/lint/rules.toml)).rules;
#       sourceRoot = ./.;
#     };
#   }
#
# Rules live in TOML (./rules.toml) rather than Nix because they ARE
# data — no Nix evaluation, interpolation, or module-system collection
# needed. TOML earns its keep here for three reasons:
#
#   1. Literal strings (`'...'`) preserve regex backslashes verbatim:
#      `pattern = '\$pbkdf2-'` is the literal pattern grep needs. In
#      Nix the same value requires `pattern = "\\$pbkdf2-"` (double
#      escape) which is a sharp edge agents trip over.
#   2. Multiline literal strings (`'''...'''`) handle the operator-
#      facing messages without escape pollution.
#   3. Portability: if the dispatcher ever escalates to commitlint-rs
#      or another language, rules.toml travels unchanged. Clean data /
#      control plane split.
#
# `builtins.fromTOML` parses with zero new tooling — TOML stays a Nix
# input, the dispatcher stays a Nix function. The file just isn't a
# Nix file.
#
# Adding a new rule = one `[rules.<name>]` block in ./rules.toml.
{ lib, pkgs }:

let
  # ── Rule schema ─────────────────────────────────────────────────
  #
  # Each rule is an attrset with:
  #
  #   pattern         — required string. Extended-regex pattern fed to
  #                     `grep -rEn`. With TOML literal strings the
  #                     value is the literal regex: `pattern = '\$pbkdf2-'`.
  #                     With Nix-declared rules, double-escape: `"\\$pbkdf2-"`.
  #   scope           — required list of strings. Paths under sourceRoot
  #                     that grep walks (e.g. `[ "modules/" ]` or
  #                     `[ "modules/" "machines/" ]`).
  #   message         — required string. Operator-facing explanation
  #                     when the rule fires. Should name the right thing
  #                     to do, not just identify the violation.
  #   excludeFiles    — optional list of strings, default `[ ]`. File
  #                     paths exempted from the rule. Matched against
  #                     the leading `<path>:<line>:` prefix of grep
  #                     output via `grep -vE`.
  #   excludePatterns — optional list of strings, default `[ ]`. Regex
  #                     fragments OR-joined into a single `grep -vE`
  #                     filter applied to each matched LINE. Use for
  #                     well-known allowlist patterns (e.g. the
  #                     `100.100.100.100` MagicDNS literal that's
  #                     legitimately not a host).
  #   docLink         — optional string, default `null`. Pointer to a
  #                     skill / runbook / doc that explains the why.
  #                     Surfaced after the message when the rule fires.
  #   tags            — optional list of strings, default `[ ]`. For
  #                     future filtering (`just lint --tag security`);
  #                     also annotated in the rule header in output.
  #
  # ── Lowering ────────────────────────────────────────────────────
  #
  # Each rule becomes a bash block:
  #
  #   1. `grep -rEn <pattern> <scope-paths>` captures matches; `|| true`
  #      because grep returns nonzero on zero matches (which is the
  #      pass case here).
  #   2. `excludeFiles` is OR-joined into a `grep -vE '^(f1|f2|...):'`
  #      filter applied to the captured output (each line starts with
  #      `<path>:<line>:` so the `:` anchor is reliable).
  #   3. `excludePatterns` is OR-joined into a second `grep -vE`
  #      applied to the same stream — pattern-level allowlist after
  #      file-level allowlist.
  #   4. If the post-filter stream is non-empty, the matches print, then
  #      the message + optional docLink, and `fail=1`.
  #
  # `-rEn` is standardized across all rules: recursive, extended-regex,
  # line-numbered. The existing scripts used a mix (`-rn`, `-rln`,
  # `-rEn`); per-rule flag selection is a variable that drifts, so it's
  # collapsed out of the schema.

  # Self-exclude: the lint module IS the rule source (the patterns
  # live as string data in modules/lint/rules.toml; the dispatcher
  # mentions them in comments). Without this exclusion every pattern
  # rule fires against its own declaration — a false positive that
  # masks real violations. The lint source isn't subject to the rules
  # it defines, the same way a grammar file isn't subject to its own
  # grammar.
  selfExcludeChain = " | grep -vE '^modules/lint/'";

  lowerRule =
    name: rule:
    let
      tagAnnotation = lib.optionalString (
        rule.tags or [ ] != [ ]
      ) " [${lib.concatStringsSep ", " rule.tags}]";

      scopePaths = lib.concatStringsSep " " rule.scope;

      fileExcludeChain =
        let
          paths = rule.excludeFiles or [ ];
        in
        if paths == [ ] then
          ""
        else
          let
            escaped = map (p: "^" + lib.escapeRegex p + ":") paths;
            joined = lib.concatStringsSep "|" escaped;
          in
          " | grep -vE ${lib.escapeShellArg joined}";

      patternExcludeChain =
        let
          patterns = rule.excludePatterns or [ ];
        in
        if patterns == [ ] then
          ""
        else
          let
            joined = lib.concatStringsSep "|" patterns;
          in
          " | grep -vE ${lib.escapeShellArg joined}";

      docLinkLine = lib.optionalString (
        rule.docLink or null != null
      ) ''printf '  → see %s\n' ${lib.escapeShellArg rule.docLink}'';

      # bash-var-safe rule name. Hyphens and dots are out; only the
      # bash-identifier subset survives. Slugify by lowercasing +
      # stripping non-alnum-underscore.
      slug = lib.replaceStrings [ "-" "." ] [ "_" "_" ] name;
    in
    ''
      # ── ${name}${tagAnnotation} ────────────────────────────────
      matches_${slug}=$(grep -rEn ${lib.escapeShellArg rule.pattern} ${scopePaths}${selfExcludeChain}${fileExcludeChain}${patternExcludeChain} || true)
      if [ -n "$matches_${slug}" ]; then
        echo
        echo "$matches_${slug}"
        echo
        printf '✗ %s\n' ${lib.escapeShellArg rule.message}
        ${docLinkLine}
        fail=1
      fi
    '';
in
{
  makeLintCheck =
    {
      rules,
      sourceRoot,
    }:
    pkgs.runCommandLocal "lint"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.gnugrep
        ];
      }
      ''
        set -u
        cd ${sourceRoot}
        fail=0

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList lowerRule rules)}

        [ "$fail" = 0 ] && touch $out
        exit "$fail"
      '';
}
