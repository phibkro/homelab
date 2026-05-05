{
  config,
  lib,
  pkgs,
  ...
}:

{

  # Ollama: local LLM inference server.
  #
  # CUDA acceleration via the host's RTX 5060 Ti (Blackwell). NixOS
  # module pulls in CUDA runtime when acceleration = "cuda"; the nvidia
  # driver itself is already configured in hosts/workstation/hardware.nix.
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
    enable = true;
    # CUDA-enabled package (replaces the deprecated acceleration = "cuda").
    # If a build issue surfaces, fall back to plain `pkgs.ollama` with
    # `acceleration = false` for CPU-only inference.
    package = pkgs.ollama-cuda;
    host = "0.0.0.0";
    port = 11434;
    openFirewall = false;
  };

  # Default-deny filesystem access beyond what ollama needs (its
  # StateDirectory at /var/lib/ollama, /dev/nvidia* for CUDA, the nix
  # store for libs). No user-data paths required. nori.harden's
  # mkForce on ProtectHome avoids Nix complaining about boolean-vs-
  # string definition collisions with the upstream module's setting.
  nori.harden.ollama = { };

  # Exposed at https://ai.nori.lan via Caddy. Monitored by Gatus
  # against /api/tags (Ollama returns 200 with the model list).
  nori.lanRoutes.ai = {
    port = 11434;
    monitor.path = "/api/tags";
  };

  # Re-derivable — Ollama's state is ~32GB of LLM weights pulled
  # via `ollama pull`, all upstream-available. Chat history lives
  # in Open WebUI's DB (covered by the open-webui repo).
  nori.backups.ollama.skip = "Re-downloadable LLM weights (~32GB). Chat history is in Open WebUI's repo.";
}
