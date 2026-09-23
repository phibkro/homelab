{ config, ... }:

let
  libraryPath = config.nori.fs.library.path;
  stagingPath = config.nori.services.music-ingest.resources.staging.path;
  stagingParent = builtins.dirOf stagingPath;
in
{
  # Shared media-library parents belong to the workstation storage
  # realization. Individual services own their resource leaves.
  systemd.tmpfiles.rules = [
    "d ${libraryPath}        02775 root media - -"
    "d ${libraryPath}/books  02775 root media - -"
    "d ${libraryPath}/comics 02775 root media - -"
    "d ${libraryPath}/manga  02775 root media - -"
    "d ${libraryPath}/papers 02775 root media - -"
    "d ${stagingParent}      0755  root root  - -"
  ];
}
