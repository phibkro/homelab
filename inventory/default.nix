{ lib }:

/**
  Pure homelab inventory compiler.

  Runs before `lib.nixosSystem`, so module selection never depends on the NixOS
  `config` fixed point. Compiler-private paths stay under `internal`; callers
  and generated tools receive only `public` or a host-scoped `forHost`
  projection.
*/

let
  hosts = import ./hosts.nix;
  profiles = import ./profiles.nix;
  workloadCatalog = import ./workloads.nix { inherit lib; };

  hostNames = lib.attrNames hosts;
  profileNames = lib.attrNames profiles;
  workloadNames = lib.attrNames workloadCatalog;

  referencedProfiles = lib.unique (lib.concatMap (host: host.profiles) (lib.attrValues hosts));
  unknownProfiles = lib.subtractLists profileNames referencedProfiles;

  referencedWorkloads = lib.unique (
    lib.concatMap (profile: profile.workloads) (lib.attrValues profiles)
    ++ lib.concatMap (host: host.workloads) (lib.attrValues hosts)
  );
  unknownWorkloads = lib.subtractLists workloadNames referencedWorkloads;
  unusedWorkloads = lib.subtractLists referencedWorkloads workloadNames;

  workloadsFor =
    hostName:
    let
      host = hosts.${hostName};
    in
    lib.sort builtins.lessThan (
      lib.unique (
        lib.concatMap (profileName: profiles.${profileName}.workloads) host.profiles ++ host.workloads
      )
    );

  hostsForWorkload =
    workloadName: lib.filter (hostName: lib.elem workloadName (workloadsFor hostName)) hostNames;

  profilesForWorkload =
    workloadName:
    lib.attrNames (lib.filterAttrs (_: profile: lib.elem workloadName profile.workloads) profiles);

  publicProfiles = lib.mapAttrs (_: profile: {
    inherit (profile) description workloads;
  }) profiles;

  publicHosts = lib.mapAttrs (
    name: host:
    host.identity
    // {
      inherit (host) profiles;
      workloads = workloadsFor name;
    }
  ) hosts;

  publicWorkloads = lib.mapAttrs (
    name: workload:
    workload
    // {
      hosts = hostsForWorkload name;
      profiles = profilesForWorkload name;
    }
  ) workloadCatalog;

  public = {
    hosts = publicHosts;
    profiles = publicProfiles;
    workloads = publicWorkloads;
  };

  forHost =
    hostName:
    assert lib.assertMsg (lib.elem hostName hostNames) "inventory.forHost: unknown host '${hostName}'";
    public
    // {
      currentHost = hostName;
      currentWorkloads = workloadsFor hostName;
    };
in
assert lib.assertMsg (
  unknownProfiles == [ ]
) "inventory: host profile reference(s) do not exist: ${lib.concatStringsSep ", " unknownProfiles}";
assert lib.assertMsg (unknownWorkloads == [ ])
  "inventory: profile/host workload reference(s) do not exist: ${lib.concatStringsSep ", " unknownWorkloads}";
assert lib.assertMsg (
  unusedWorkloads == [ ]
) "inventory: catalog workload(s) have no placement: ${lib.concatStringsSep ", " unusedWorkloads}";
{
  inherit public forHost;

  internal = {
    inherit
      hosts
      profiles
      workloadCatalog
      workloadsFor
      ;
  };
}
