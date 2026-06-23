{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nori.musicIngest;
  libraryPath = config.nori.fs.library.path;

  # The ingest logic lives as a standalone script (./music-ingest.sh) so the
  # fixture test (./music-ingest.test.sh) can invoke it directly against a /tmp
  # tree — same artifact the unit runs, no second copy of the logic to drift.
  # writeShellApplication pins b3sum + coreutils into the closure (the unit's
  # PATH guesses nothing) AND shellchecks the script at build time, so a shell
  # bug fails `nix flake check` rather than a 3am timer run.
  ingestScript = pkgs.writeShellApplication {
    name = "music-ingest";
    runtimeInputs = [
      pkgs.b3sum
      pkgs.coreutils
      pkgs.findutils
    ];
    text = builtins.readFile ./music-ingest.sh;
  };
in
{
  options.nori.musicIngest = {
    enable = lib.mkEnableOption "timer-driven MOVE of stable FLAC from a Syncthing staging dir into the master music library";

    stagingPath = lib.mkOption {
      type = lib.types.str;
      # No default — the caller declares the Syncthing staging dir. A surprising
      # default here would be a latent bug: the master is irreplaceable, and the
      # staging dir is the ONLY place this job deletes from. Intent is explicit.
      example = "/mnt/media/library/music-staging";
      description = ''
        Transient Syncthing sendreceive folder the phone pushes new FLAC into.
        The ingest job MOVES complete, stable files out of here into the master
        library and deletes the staging copy (a separate Syncthing folder then
        propagates that delete to the phone, freeing its FLAC). MUST be a
        separate path from the master library — the master must never be the
        thing the phone can delete from.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = ''
        systemd OnUnitActiveSec cadence between ingest sweeps. A sweep is cheap
        when staging is empty (one find). Default: every 15 minutes.
      '';
    };

    stabilitySeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 60;
      description = ''
        A FLAC is ingested only if its mtime is older than this window — i.e.
        not mid-write. Pairs with the Syncthing-temp-sibling guard. Default 60s.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nori.fs ? library;
        message = "nori.musicIngest needs nori.fs.library (the host holding the master music library).";
      }
      {
        # Structural guard against the contamination incident (runbook
        # music-opus-mirror.md): staging nested inside the master would let the
        # phone's deletes reach the master. Keep them disjoint.
        assertion = !(lib.hasPrefix "${libraryPath}/music/" "${cfg.stagingPath}/");
        message = "nori.musicIngest.stagingPath (${cfg.stagingPath}) must NOT be inside the master ${libraryPath}/music — the master must never be deletable via the staging Syncthing folder.";
      }
    ];

    # Dedicated system user; `media` group is load-bearing — library/music is
    # root:media 02775, so a media-group user creates the temp file + renames
    # into the tree without owning it. Mirrors music-mirror.nix.
    users.users.music-ingest = {
      isSystemUser = true;
      group = "music-ingest";
      extraGroups = [ "media" ];
      home = "/var/empty";
      description = "FLAC staging→master music library ingest";
    };
    users.groups.music-ingest = { };

    systemd.services.music-ingest = {
      description = "FLAC staging→master ingest (one sweep)";
      after = [ "local-fs.target" ];
      environment = {
        MUSIC_INGEST_STAGING = cfg.stagingPath;
        MUSIC_INGEST_LIBRARY = libraryPath;
        MUSIC_INGEST_STABILITY_SECONDS = toString cfg.stabilitySeconds;
      };
      serviceConfig = {
        Type = "oneshot";
        User = "music-ingest";
        Group = "music-ingest";
        ExecStart = "${ingestScript}/bin/music-ingest";
        # Group-writable output (0775 dirs / 0664 files) so the ingested FLAC is
        # readable+writable by the rest of the media group (Navidrome, the Opus
        # mirror, an operator). Mirrors music-mirror's UMask.
        UMask = "0002";
        # exit 3 = "conflict quarantined, operator action needed" — surface it
        # so an OnFailure→ntfy alert fires, but don't treat the other ingested
        # work as failed.
        SuccessExitStatus = [ 3 ];
        # Background work — never starve the desktop / Navidrome / a real build.
        Nice = 12;
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "batch";
      };
    };

    systemd.timers.music-ingest = {
      description = "Periodic FLAC staging→master ingest";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.interval;
        OnUnitActiveSec = cfg.interval;
        Persistent = true; # catch up one missed run after the box wakes/boots
        RandomizedDelaySec = "60";
      };
    };

    # Default-deny FS hardening. RW BOTH the master library (atomic move target)
    # AND the staging dir (the job deletes from it). Same bind shape as
    # music-mirror.nix / syncthing.nix.
    nori.harden.music-ingest.binds = [
      libraryPath
      cfg.stagingPath
    ];

    # Staging is transient (Syncthing-replicated, freed on ingest) → no backup
    # intent for it. The master library it feeds (nori.fs.library, tier
    # "irreplaceable") already carries the backup policy — ingest is a local
    # MOVE into an already-protected tree, not a new data home.
    nori.backups.music-ingest.skip = "staging is transient (Syncthing-replicated); ingested FLAC lands in nori.fs.library (already irreplaceable-tier backed up).";
  };
}
