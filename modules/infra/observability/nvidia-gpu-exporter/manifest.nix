{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "observability"
    "gpu-bound"
  ];
}
