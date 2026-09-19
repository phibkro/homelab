/*
  Explicit reusable compositions.

  Profiles select reusable system modules only. `systemModules` is
  compiler-private and selected before NixOS evaluation.
*/
{
  base = {
    description = "Common host baseline, realized by its deployment backend";
    systemModules = [ ../infra/common/nixos/default.nix ];
  };

  desktop = {
    description = "Operator-attached graphical workstation";
    systemModules = [ ../profiles/desktop/nixos/default.nix ];
  };

  log-forwarder = {
    description = "Per-host journald shipping to the central log index";
    systemModules = [ ../services/vector/nixos.nix ];
  };

  backup-source = {
    description = "Local rollback snapshots and explicitly enabled independent backup policy";
    systemModules = [
      ../services/btrbk/nixos.nix
      ../services/restic-backup/nixos.nix
      ../services/restore-drill/nixos.nix
    ];
  };

  research = {
    description = "Operator research acquisition tools colocated with their data sink";
    systemModules = [ ../profiles/research/nixos.nix ];
  };

  media-compute = {
    description = "GPU media serving, acquisition, and operator AI";
    systemModules = [ ];
  };

  family-vault = {
    description = "Always-on family data and application tier";
    systemModules = [ ];
  };

  entry-plane = {
    description = "Always-on HTTP, DNS, identity, alert, and metrics hub";
    # Production realization is exclusively Ansible-owned under infra/pi/.
    systemModules = [ ];
  };

  observability-agent = {
    description = "Per-host metrics exporters and high-level agent";
    systemModules = [ ];
  };

}
