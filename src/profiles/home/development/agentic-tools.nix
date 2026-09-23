/**
  Security-sensitive coding-agent capability.

  Provider runtimes, global skills, sandbox policy, and halt notifications are
  selected together for trusted operator PCs. Host-specific dispatch wrappers
  and credentials remain in the machine realization that owns them.
*/
{
  imports = [
    ../../../users/nori/programs/agent-notify
    ../../../users/nori/programs/agent-skills
    ../../../users/nori/programs/claude-code
    ../../../users/nori/programs/omp
    ../../../users/nori/programs/omp-lsp
  ];
}
