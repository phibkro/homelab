{
  inputs,
  lib,
  pkgs,
  ...
}:

/**
  Provider-neutral operator skills. Keep the canonical source here and expose
  the same directory to every installed agent surface so procedure and safety
  policy cannot drift between OMP, Claude Code, and Codex.
*/

let
  agentPackages = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  agentBrowserSkill = ./agent-browser;
  simpleEnglishSkill = ./simple-english;
  writingPythonSkill = ./writing-python;
  devenvSkill = ./devenv;

  /*
    Pinned upstream skill trees consumed directly from flake inputs. Skills
    are read-only guidance, so a source pin per repo is the whole version
    contract: bumping the input bumps every surface at once.
  */
  foldkitSkills = "${inputs.foldkit-src}/skills";
  effectSkills = "${inputs.effect-skills}/skills";
  effectTsSkill = pkgs.runCommandLocal "effect-ts-agent-skill" { } ''
    mkdir -p "$out"
    cp -R ${effectSkills}/effect-ts/. "$out/"
    chmod u+w "$out/SKILL.md"
    cat ${./effect-ts-lsp.md} >>"$out/SKILL.md"
  '';

  /*
    One source, every surface. Two copies of a procedure is a representable
    illegal state, and it had already gone wrong: ~/.codex/skills/herdr was an
    undeclared source checkout whose SKILL.md sat 150 lines away from the
    pinned copy Claude reads, so the two providers were following different
    control-plane contracts.
  */
  bothSurfaces = name: source: {
    ".omp/agent/skills/${name}" = {
      inherit source;
      recursive = true;
    };
    ".claude/skills/${name}" = {
      inherit source;
      recursive = true;
    };
    ".codex/skills/${name}" = {
      inherit source;
      recursive = true;
    };
  };

  bothSurfacesFile = path: source: {
    ".omp/agent/skills/${path}".source = source;
    ".claude/skills/${path}".source = source;
    ".codex/skills/${path}".source = source;
  };
in
{
  home.packages = [
    agentPackages.agent-browser
    # Runtime for .agents/skills/manage-genexis-juci.
    pkgs.python3
    pkgs.websocat
  ];

  home.file = lib.mkMerge [
    (bothSurfaces "agent-browser" agentBrowserSkill)

    /*
      ASD-STE100 Simplified Technical English writing skill (MIT-licensed,
      provider-neutral prose rules). Canonical here; previously a loose
      undeclared checkout in ~/.codex/skills only — the exact drift state
      the herdr incident above describes.
    */
    (bothSurfaces "simple-english" simpleEnglishSkill)

    /*
      Idiomatic + performant Python: Hettinger's transformation table, the
      ruff families that enforce part of it, and the patterns NO linter
      catches. That last list is the reason the skill exists — ruff has 968
      rules and implements about 40% of the talk, and it catches none of the
      `range(len(...))` rewrites, so those must be read for by eye.
    */
    (bothSurfaces "writing-python" writingPythonSkill)

    (bothSurfaces "devenv" devenvSkill)

    /*
      Foldkit AI integration, skill half: the framework's own Elm-architecture
      framing, app generator, and audit workflow, mirrored from the pinned
      upstream tree. The other half — live runtime inspection — is the
      foldkit-devtools MCP server registered in each Foldkit project's
      .omp/mcp.json (clamor today).
    */
    (bothSurfaces "foldkit" "${foldkitSkills}/foldkit")
    (bothSurfaces "generate-program" "${foldkitSkills}/generate-program")
    (bothSurfaces "audit-program" "${foldkitSkills}/audit-program")

    /*
      Official Effect-TS skills from the pinned upstream source. `effect-ts`
      delegates version-specific guidance to the installed Effect package's
      own AGENTS.md. The local appendix adds only project-local Effect language
      tooling setup and OMP verification after the untouched official skill.
      `effect-v3-to-v4` owns the migration workflow.
    */
    (bothSurfaces "effect-ts" effectTsSkill)
    (bothSurfaces "effect-v3-to-v4" "${effectSkills}/effect-v3-to-v4")

    /*
      Pagu remains installed as an agent-launch runtime, but its discoverable
      skill is deliberately disabled for now.

      Herdr publishes its agent contract alongside its executable. Consume both
      from the same pinned flake revision so guidance and behavior move together.
      Linux only: the Intel Mac installs neither Herdr nor a Codex surface.
    */
    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      bothSurfacesFile "herdr/SKILL.md" "${inputs.herdr}/SKILL.md"
    ))
  ];
}
