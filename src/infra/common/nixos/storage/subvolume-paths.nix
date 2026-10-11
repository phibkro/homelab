let
  stagingSuffix = ".nori-subvolume-migration-staging";
  rollbackSuffix = ".nori-subvolume-migration-rollback";
in
{
  inherit stagingSuffix rollbackSuffix;
  forPath = path: {
    inherit path;
    staging = builtins.dirOf path + "/." + builtins.baseNameOf path + stagingSuffix;
    rollback = builtins.dirOf path + "/." + builtins.baseNameOf path + rollbackSuffix;
  };
}
