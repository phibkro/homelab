{
  music = {
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
}
