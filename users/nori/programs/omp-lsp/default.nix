{
  inputs,
  pkgs,
  ...
}:

let
  pkgsMaster = inputs.nixpkgs-master.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  typescriptRouter = pkgs.writeShellApplication {
    name = "omp-typescript-language-server";
    runtimeInputs = [ pkgsMaster.bun ];
    text = ''
      export OMP_TYPESCRIPT_LANGUAGE_SERVER="${pkgsMaster.typescript-language-server}/bin/typescript-language-server"
      exec bun ${./typescript-router.mjs} "$@"
    '';
  };

  tyWrapper = pkgs.writeShellApplication {
    name = "omp-ty";
    runtimeInputs = [ pkgsMaster.ty ];
    text = ''
      export TY_CONFIG_FILE="${./ty.toml}"
      exec ty "$@"
    '';
  };
in
{
  home.packages = [
    pkgsMaster.ruff
    pkgsMaster.rust-analyzer
    pkgsMaster.ty
    pkgsMaster.typescript-language-server
    pkgsMaster.uv
    typescriptRouter
    tyWrapper
  ];

  home.file.".omp/agent/lsp.json".source = ./lsp.json;
}
