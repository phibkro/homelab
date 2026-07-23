{ pkgs, ... }:

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
in
{
  home.packages = [
    pkgs.python3
    pkgs.websocat
  ];

  home.file = {
    ".claude/skills/manage-genexis-juci" = {
      source = genexisJuciSkill;
      recursive = true;
    };
    ".codex/skills/manage-genexis-juci" = {
      source = genexisJuciSkill;
      recursive = true;
    };
  };
}
