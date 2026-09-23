{ config, ... }:

let
  cfg = config.nori.services.music-ingest;
  stagingParent = "/mnt/media/staging";
in
{
  /*
    Workstation binding for the music-ingest job. The staging tree lives on
    the workstation root filesystem: only /mnt/media/library is the mounted
    IronWolf filesystem. Inflight is a sibling of the Syncthing folder so a
    claim rename stays atomic without making durable claims phone-managed
    state.

    The master path is derived from the canonical filesystem and dataset
    declarations. Do not replace it with a second physical path literal.
  */
  nori.services.music-ingest.resources = {
    staging = {
      path = "${stagingParent}/music-flac";
      filesystem = "root";
    };
    inflight = {
      path = "${stagingParent}/.music-ingest-inflight";
      filesystem = "root";
    };
    master = {
      path = "${config.nori.fs.library.path}/${config.nori.inventory.datasets.music.storage.relativePath}";
      filesystem = config.nori.inventory.datasets.music.storage.filesystem;
    };
  };

  /*
    Give Syncthing writable access to the declared staging resource so it can
    place received files there. Folder membership and remote propagation are
    runtime configuration and must be verified separately.
  */
  nori.harden.syncthing.binds = [ cfg.resources.staging.path ];

  /*
    Received directories must remain writable by the shared media group so
    the ingest principal can remove its claimed source entries.
  */
  systemd.services.syncthing.serviceConfig.UMask = "0002";
}
