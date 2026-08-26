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
  agentBrowserSkill = ./agent-browser;
  simpleEnglishSkill = ./simple-english;
  writingPythonSkill = ./writing-python;
  effectV4Skill = ./effect-v4-engineer;

  /*
    Pinned upstream skill trees consumed directly from flake inputs. Skills
    are read-only guidance, so a source pin per repo is the whole version
    contract: bumping the input bumps every surface at once.
  */
  foldkitSkills = "${inputs.foldkit-src}/skills";
  effectSkills = "${inputs.effect-skills}/skills";

  /*
    One source, every surface. Two copies of a procedure is a representable
    illegal state, and it had already gone wrong: ~/.codex/skills/herdr was an
    undeclared source checkout whose SKILL.md sat 150 lines away from the
    pinned copy Claude reads, so the two providers were following different
    control-plane contracts.
  */
  bothSurfaces =
    name: source:
    {
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

  bothSurfacesFile =
    path: source:
    {
      ".omp/agent/skills/${path}".source = source;
      ".claude/skills/${path}".source = source;
      ".codex/skills/${path}".source = source;
    };
in
{
  home.packages = [
    pkgs.agent-browser
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

    /*
      Effect v4 as the default application language: schema boundaries,
      services and Layers, and the module-role classification that stops an
      agent reaching for ambient plain TypeScript. Canonical here; previously
      an undeclared checkout in ~/.codex/skills only, so Claude could not read
      it at all while Codex could — the same one-surface drift the herdr and
      simple-english entries above record.

      It matters more than most: v4 is in beta, its ecosystem still publishes
      v3 under `latest`, and an agent working from remembered v3 APIs writes
      code that type-checks against documentation and fails against the
      installed package.
    */
    (bothSurfaces "effect-v4-engineer" effectV4Skill)

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
      Effect v4 AI tooling, upstream half: mikearnaldi's Effect-TS/skills —
      effect-ts points agents at the installed package's own AGENTS.md (the
      authoritative v4 API reference), effect-v3-to-v4 drives migrations from
      the generated migration reference. Complements effect-v4-engineer,
      which stays homelab-owned policy rather than duplicated upstream prose.
    */
    (bothSurfaces "effect-ts" "${effectSkills}/effect-ts")
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
