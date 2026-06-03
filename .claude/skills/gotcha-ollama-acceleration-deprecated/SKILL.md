---
name: gotcha-ollama-acceleration-deprecated
description: USE WHEN configuring CUDA support for Ollama — `services.ollama.acceleration = "cuda"` is removed in current nixpkgs. Use `package = pkgs.ollama-cuda` instead. First build is slow (~30 min) — nvcc compiles GGML for many CUDA arches and binary cache often misses.
---

# `services.ollama.acceleration = "cuda"` is deprecated

Removed in current nixpkgs. Use `package = pkgs.ollama-cuda` instead. First build of `ollama-cuda` is slow (~30 min) — nvcc compiles GGML for many CUDA arches and binary cache often misses.
