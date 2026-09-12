{
  source,
  profile,
  profileHash,
  host ? "workstation",
}:
let
  sourcePath = builtins.toPath source;
  fullProfile = builtins.fromJSON (builtins.readFile profile);
  profileProjection = {
    formatVersion = fullProfile.formatVersion;
    revision = fullProfile.revision;
    components = fullProfile.components;
  };
  generationMetadata = {
    source = toString sourcePath;
    profileRevision = profileProjection.revision;
    inherit profileHash;
  };
  approvedFlake = builtins.getFlake "path:${toString sourcePath}";
  baseConfiguration = approvedFlake.nixosConfigurations.${host};
  configuration = baseConfiguration.extendModules {
    modules = [
      {
        home-manager.users.nori.nori.desktop.profile = profileProjection;
        environment.etc."nori-desktop-settings/generation.json" = {
          mode = "0444";
          text = builtins.toJSON generationMetadata;
        };
      }
    ];
  };
in
{
  toplevel = configuration.config.system.build.toplevel;
  resolved = configuration.config.home-manager.users.nori.nori.desktop.resolved.components;
  metadata = configuration.pkgs.writeText "nori-desktop-settings-generation.json" (
    builtins.toJSON generationMetadata
  );
}
