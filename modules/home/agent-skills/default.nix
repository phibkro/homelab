{
  inputs,
  lib,
  pkgs,
  ...
}:

/**
  Provider-neutral operator skills. Keep the canonical source here and expose
  the same directory to every installed agent surface so procedure and safety
  policy cannot drift between Claude and Codex.

  This module is selected by the agentic-tools capability: router
  administration is an operator capability and does not belong on service
  appliances.
*/

let
  genexisJuciSkill = ./manage-genexis-juci;
  simpleEnglishSkill = ./simple-english;
  writingPythonSkill = ./writing-python;
  effectV4Skill = ./effect-v4-engineer;

  /*
    One source, every surface. Two copies of a procedure is a representable
    illegal state, and it had already gone wrong: ~/.codex/skills/herdr was an
    undeclared source checkout whose SKILL.md sat 150 lines away from the
    pinned copy Claude reads, so the two providers were following different
    control-plane contracts.
  */
  bothSurfaces = name: source: {
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
    ".claude/skills/${path}".source = source;
    ".codex/skills/${path}".source = source;
  };
in
{
  home.packages = [
    pkgs.python3
    pkgs.websocat
  ];

  home.file = lib.mkMerge [
    (bothSurfaces "manage-genexis-juci" genexisJuciSkill)

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
      pagu and herdr publish their own agent contracts. Consume each from the
      same pinned flake revision that supplies its executable, so the guidance
      and the behaviour it describes can only move together — the `generate`
      rung rather than the `convention` rung.

      Linux only: the Intel Mac installs neither the `pagu` gate nor herdr, and
      has no Codex surface either.
    */
    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      lib.mkMerge [
        (bothSurfaces "pagu" "${inputs.pagu}/skills/pagu")
        # Herdr publishes its contract as a single file at the repository root.
        (bothSurfacesFile "herdr/SKILL.md" "${inputs.herdr}/SKILL.md")
      ]
    ))
  ];
}
