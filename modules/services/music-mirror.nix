{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nori.musicMirror;
  # Reuse tonic's backend derivation purely for its `tonic-mirror` console
  # script (the FLAC→Opus library mirror). This is the transcode half of tonic
  # running standalone — no daemon, no PWA, no Qobuz/Spotify acquisition. The
  # operator acquires FLAC however they like (SpotiFLAC-Mobile → Syncthing
  # today); this just keeps an Opus mirror of the library current.
  backendPkg = inputs.tonic.packages.${pkgs.system}.backend;
  libraryPath = config.nori.fs.library.path;
in
{
  options.nori.musicMirror = {
    enable = lib.mkEnableOption "timer-driven FLAC→Opus mirror of the music library";
    interval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/15";
      description = ''
        systemd OnCalendar for the mirror sweep. The sweep is cheap when nothing
        changed (a stat per file via the mtime fast-path; the blake3 hash is paid
        only for new/changed FLACs), so a tight cadence is fine. Default: every
        15 minutes.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nori.fs ? library;
        message = "nori.musicMirror needs nori.fs.library (the host holding the music library).";
      }
    ];

    # Dedicated system user; `media` group is load-bearing — library/{music,
    # music-opus} are root:media 02775, so a media-group user reads the FLACs
    # and writes the Opus mirror without owning the tree.
    users.users.music-mirror = {
      isSystemUser = true;
      group = "music-mirror";
      extraGroups = [ "media" ];
      home = "/var/empty";
      description = "FLAC→Opus music library mirror";
    };
    users.groups.music-mirror = { };

    # Ensure the Opus mirror root exists, group-writable + setgid so new
    # subdirs inherit root:media (matches the FLAC tree's ownership model).
    systemd.tmpfiles.rules = [
      "d ${libraryPath}/music-opus 2775 root media - -"
    ];

    systemd.services.music-mirror = {
      description = "FLAC→Opus library mirror (one sweep)";
      after = [ "local-fs.target" ];
      # opusenc + opusinfo on PATH for the transcode + idempotency check.
      path = [ pkgs.opus-tools ];
      environment = {
        TONIC_MUSIC_ROOT = "${libraryPath}/music";
        TONIC_OPUS_ROOT = "${libraryPath}/music-opus";
      };
      serviceConfig = {
        Type = "oneshot";
        User = "music-mirror";
        Group = "music-mirror";
        ExecStart = "${backendPkg}/bin/tonic-mirror";
        # Group-writable output (0775 dirs / 0664 files) so any media-group
        # writer — the service OR an operator running `tonic-mirror` by hand —
        # can update the tree. Without this, a hand-run leaves owner-only dirs
        # the service then can't write into.
        UMask = "0002";
        # Background work — never starve the desktop / Navidrome / a real build.
        Nice = 12;
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "batch";
      };
    };

    systemd.timers.music-mirror = {
      description = "Periodic FLAC→Opus library mirror";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true; # catch up one missed run after the box wakes/boots
        RandomizedDelaySec = "60";
      };
    };

    # Default-deny FS hardening; RW the library subvol (reads music/, writes
    # music-opus/). Same bind shape as syncthing.nix / tonic.nix.
    nori.harden.music-mirror.binds = [ libraryPath ];

    # Re-derivable from the FLAC library — nothing to back up.
    nori.backups.music-mirror.skip = "music-opus is a re-runnable derivation of ${libraryPath}/music (the lossless FLAC library).";
  };
}
