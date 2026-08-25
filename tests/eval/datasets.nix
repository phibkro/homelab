{
  inputs,
  lib,
  ...
}:

/**
  Dataset contract projection test.

  The logical music root is declared once in pure inventory, then resolved
  against each host's local filesystem realization by producers and consumers.
*/
let
  inventory = inputs.self.lib.noriInventory;
  music = inventory.datasets.music;
  workstation = inputs.self.nixosConfigurations.workstation.config;

  expected = {
    description = "Lossless canonical music library and its delivery contract";
    valueTier = "irreplaceable";
    canonicalFormat = "flac";
    storage = {
      filesystem = "library";
      relativePath = "music";
    };
    producers = [
      "lidarr"
      "music-ingest"
    ];
    consumers = [ "navidrome" ];
    derivedFormats = [ ];
    delivery = {
      protocol = "subsonic";
      transcodeOnDemand = [
        "opus"
        "mp3"
      ];
      persistentDerivative = false;
    };
  };

  relationshipsResolve = lib.all (workloadName: inventory.workloads.${workloadName}.hosts != [ ]) (
    music.producers ++ music.consumers
  );

  runtimePathsResolve =
    workstation.systemd.services.music-ingest.environment.MUSIC_INGEST_MASTER
    == "/mnt/family/library/music"
    && lib.elem "/mnt/family/library/music" workstation.nori.harden.lidarr.binds
    && workstation.services.navidrome.settings.MusicFolder == "/mnt/family/library/music"
    && workstation.nori.harden.navidrome.readOnlyBinds == [ "/mnt/family/library/music" ];
in
if music == expected && relationshipsResolve && runtimePathsResolve then
  "ok — music dataset is canonical and every runtime resolves its host-local path"
else
  throw ''
    Dataset contract mismatch.
    Expected: ${builtins.toJSON expected}
    Actual:   ${builtins.toJSON music}
    Relationships resolve: ${toString relationshipsResolve}
    Runtime paths resolve:  ${toString runtimePathsResolve}
  ''
