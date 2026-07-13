{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:

buildGoModule rec {
  pname = "cliproxyapi";
  version = "7.2.72";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-mk2te2FypISUdzxroq7WpN5SeD3fdGoWQ+w0z6k6rw8=";
  };

  subPackages = [ "cmd/server" ];
  vendorHash = "sha256-vQU3hLDga5PMUwH4KSB3T5sZ1uPUgHQHeyQGJTKHIYs=";

  # Upstream's -local-model skips remote model catalogs but still starts an
  # unrelated Antigravity updater. Keep this Codex-only proxy quiet instead.
  postPatch = ''
    substituteInPlace cmd/server/main.go \
      --replace-fail 'misc.StartAntigravityVersionUpdater(context.Background())' \
      'if !localModel { misc.StartAntigravityVersionUpdater(context.Background()) }'
  '';

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
    "-X main.Commit=6279bb8a4c2835ff6ed99c6b85083b2afbefa681"
    "-X main.BuildDate=1970-01-01T00:00:00Z"
  ];

  postInstall = ''
    mv "$out/bin/server" "$out/bin/cliproxyapi"
  '';

  meta = {
    description = "Anthropic/OpenAI-compatible local proxy for coding-agent OAuth providers";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    license = lib.licenses.mit;
    mainProgram = "cliproxyapi";
    platforms = lib.platforms.linux;
  };
}
