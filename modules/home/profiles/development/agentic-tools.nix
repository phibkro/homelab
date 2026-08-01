/**
  Security-sensitive coding-agent capability.

  Provider runtimes, global skills, sandbox policy, and halt notifications are
  selected together for trusted operator PCs. Host-specific dispatch wrappers
  and credentials remain in the machine realization that owns them.
*/
{
  imports = [
    ../../agent-notify
    ../../agent-skills
    ../../claude-code
    ../../omp
  ];
}
