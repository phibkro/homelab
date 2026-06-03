{
  lib,
  pkgs,
  inputs,
  ...
}:

let
  # Paused 2026-05-16 — operator not using local LLM inference recently,
  # the GPU + ~14 GiB VRAM at idle was not worth the cost. Flip to
  # `true` to resume. State at /var/lib/ollama is preserved across the
  # toggle (NixOS doesn't reap StateDirectory on disable). Flipping
  # this single boolean restores:
  #   * the systemd unit + CUDA acceleration
  #   * the https://ai.nori.lan Caddy route
  #   * Gatus monitor + Glance dashboard entry (both downstream of
  #     nori.lanRoutes.ai)
  enabled = true;
in
{

  # Ollama: local LLM inference server.
  #
  # CUDA acceleration via the host's RTX 5060 Ti (Blackwell). NixOS
  # module pulls in CUDA runtime when acceleration = "cuda"; the nvidia
  # driver itself is already configured in machines/workstation/hardware.nix.
  #
  # Models live at /var/lib/ollama/models (the module's default), owned
  # by the ollama service user. Restore the previous library from the
  # Ubuntu One Touch backup (~34 GB) by rsync'ing
  #   nori-backup-20260424T223707Z/ollama-share/models/
  # → /var/lib/ollama/models/ AFTER the service has started once
  # (so the directory exists with correct ownership).
  #
  # Exposed on the tailnet at port 11434. No backup — DESIGN tier table
  # treats models as re-derivable; the One Touch holds a snapshot for
  # convenience but isn't load-bearing.

  services.ollama = {
    enable = enabled;
    # CUDA-enabled package, pulled from the local nixpkgs fork at
    # `ollama-0.30.3` (input `nixpkgs-ollama` in ../../flake.nix). The
    # bump is needed for mxfp8 / nvfp4 quants — stable 26.05 ships
    # 0.24.0, which fails pulls with HTTP 412 on those quants. Revert
    # to `pkgs.ollama-cuda` once nixpkgs upstreams the bump (PR open
    # from this branch); the input goes with it.
    #
    # `legacyPackages` evaluates with default (allowUnfree=false,
    # cudaSupport=false), which rejects ollama-cuda's CUDA closure —
    # import the fork's nixpkgs ourselves with our config to bypass.
    package =
      (import inputs.nixpkgs-ollama {
        system = pkgs.stdenv.hostPlatform.system;
        config = {
          allowUnfree = true;
          cudaSupport = true;
        };
      }).ollama-cuda;
    host = "0.0.0.0";
    port = 11434;
    openFirewall = false;

    # Unload models from VRAM as soon as a request completes. Default
    # is 5m which means one chat reserves ~14 GiB VRAM for five minutes
    # after the last token. With `0` the base Ollama process holds
    # only its own ~50 MB and VRAM is free for the next consumer (e.g.
    # Immich ML, Jellyfin transcode) between requests. Trade-off:
    # first-token latency on the next request pays the model-load cost
    # again (~1-3s for typical models). Acceptable for low-frequency
    # interactive use; flip to "5m" if doing burst-style chat sessions.
    environmentVariables.OLLAMA_KEEP_ALIVE = "0";

    # loadModels intentionally unset.
    #
    # Pulls are now done manually first, then this list is filled in once a
    # tag is confirmed to load on the running daemon:
    #   sudo -u ollama OLLAMA_HOST=127.0.0.1:11434 ollama pull <tag>
    # Repeat pulls of a present model are no-ops, so adding the tag here
    # after a successful manual pull is safe (and survives reinstalls).
    #
    # The 0.24-era restart-loop hazard
    # (.claude/skills/gotcha-systemd-restart-loop-bombs/) was: setting
    # loadModels to a tag the daemon rejects → systemd respawns every
    # 10s → cascade. The Ollama 0.30 bump (see `package` above) clears
    # the mxfp8 / nvfp4 rejection class. Still verify any new tag via
    # manual pull before listing it here.
    #
    # Candidates (gemma4 family): gemma4:12b (general, ~12GB mxfp8 in
    # 16GB VRAM), gemma4:12b-nvfp4 (Blackwell FP4, ~6-7GB), gemma3:12b
    # (older gen, works on any Ollama).
  };

  # Default-deny filesystem access beyond what ollama needs (its
  # StateDirectory at /var/lib/ollama, /dev/nvidia* for CUDA, the nix
  # store for libs). No user-data paths required. nori.harden's
  # mkForce on ProtectHome avoids Nix complaining about boolean-vs-
  # string definition collisions with the upstream module's setting.
  nori.harden.ollama = { };

  # Exposed at https://ai.nori.lan via Caddy. Monitored by Gatus
  # against /api/tags (Ollama returns 200 with the model list).
  nori.lanRoutes = lib.mkIf enabled {
    ai = {
      port = 11434;
      monitor.path = "/api/tags";
    };
  };

  # Re-derivable — Ollama's state is ~32GB of LLM weights pulled
  # via `ollama pull`, all upstream-available. Chat history lives
  # in Open WebUI's DB (covered by the open-webui repo).
  nori.backups.ollama.skip =
    if enabled then
      "Re-downloadable LLM weights (~32GB). Chat history is in Open WebUI's repo."
    else
      "Service disabled — see `enabled` at top of file.";
}
