{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nori.papersFetch;

  /*
    The resolver lives as a standalone Python file (./papers-fetch.py) so it
    can be run + tested directly (the live-API journey in the P1 commit message)
    — same artifact the CLI wraps, no second copy to drift. writePython3Bin
    pins the dep closure (arxiv + habanero + httpx, plus habanero's transitive
    `packaging`) AND flake8-lints at build time, so a Python bug fails
    `nix flake check` rather than a runtime crash.
  */
  fetchScript = pkgs.writers.writePython3Bin "papers-fetch-core" {
    libraries = with pkgs.python3Packages; [
      arxiv
      habanero
      httpx
    ];
    # OpenAlex/Unpaywall responses carry keys this tool doesn't read; the
    # script is deliberately permissive about dict shape, so silence flake8's
    # complexity/line-length noise rather than contort the resolver.
    flakeIgnore = [
      "E501"
      "E722"
      # writePython3Bin prepends its own shebang, so the script's `#!/usr/bin/env
      # python3` (kept for standalone runs / tests) lands mid-file and trips E265.
      "E265"
    ];
  } (builtins.readFile ./papers-fetch.py);

  /*
    Thin wrapper that bakes the operator's standing config (consume dir +
    contact email) into the call, so the operator just runs
    `papers-fetch <doi|arxiv-id|title>`. Caller declares intent once in
    config; the CLI guesses nothing.
  */
  papersFetch = pkgs.writeShellApplication {
    name = "papers-fetch";
    runtimeInputs = [ fetchScript ];
    text = ''
      exec papers-fetch-core \
        --out-dir ${lib.escapeShellArg cfg.consumeDir} \
        --email ${lib.escapeShellArg cfg.email} \
        ${lib.optionalString cfg.allowGrayZone "--allow-gray-zone"} \
        "$@"
    '';
  };
in
{
  /*
    papers-fetch — the OA-first resolver/fetcher half of the papers
    acquisition pipeline (docs/specs/2026-06-23-papers-acquisition.md).
    Resolves a DOI / arXiv-id / title → open-access PDF → drops it in
    Paperless-ngx's consume dir, which OCRs + indexes + serves it.

    Resolution chain (legal, OA-first): arXiv → Unpaywall → OpenAlex,
    with Crossref turning a free-text title into a DOI first. No gray-zone
    registries (Sci-Hub/Anna's) — the `allowGrayZone` flag exists only to
    surface the opt-in posture; the resolver raises if it's flipped (the
    legal chain is the whole product). cf. tonic ADR-0010 (no scraped
    creds / UA impersonation) — the only UA trick here is a browser UA on
    the *download* of an already-OA-licensed PDF past blunt publisher
    filters, not credentialed access.

    Not a service: no daemon, no port, no state. Just a CLI on PATH (P2's
    search front-end + P3's reading-list sync are deferred per the spec).
    The Paperless sink (modules/services/paperless.nix) owns everything
    downstream of the consume dir.

    Usage (on the host where Paperless runs, or any host sharing the
    consume dir):
      papers-fetch 1706.03762                      # arXiv id
      papers-fetch 10.1371/journal.pone.0173664    # DOI
      papers-fetch "Attention is all you need"     # title → Crossref → DOI
  */
  options.nori.papersFetch = {
    enable = lib.mkEnableOption "the OA-first papers fetcher CLI (papers-fetch)";

    consumeDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.services.paperless.consumptionDir}";
      defaultText = lib.literalExpression "config.services.paperless.consumptionDir";
      description = ''
        Directory the fetched PDF is dropped into — Paperless's consume dir
        by default. Paperless's consumer must be able to read it and the
        invoking operator must be able to write it (on aurora the consume dir
        is made group/world-writable via services.paperless.consumptionDirIsPublic).
      '';
    };

    email = lib.mkOption {
      type = lib.types.str;
      # No default: Unpaywall + OpenAlex + Crossref require a contact email in
      # the polite-pool query string. Not a secret (it's sent in cleartext to
      # public APIs), but it identifies the caller — make the caller declare it.
      example = "you@example.com";
      description = ''
        Contact email sent to Unpaywall / OpenAlex / Crossref (their polite-pool
        convention — earns a faster rate limit; not a secret, not auth).
      '';
    };

    allowGrayZone = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Opt into gray-zone registries (Sci-Hub / Anna's). OFF by default and
        NOT implemented — the resolver raises if set. Present only so the
        opt-in posture is explicit in config rather than hidden in the script.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.email != "";
        message = "nori.papersFetch.email must be set (Unpaywall/OpenAlex/Crossref require a contact email).";
      }
    ];
    environment.systemPackages = [ papersFetch ];
  };
}
