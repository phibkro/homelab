{
  # The last and current GitLab package versions observed across the deployed
  # system generations. Keep the exact review endpoints here; the module guard
  # permits later patches within the reviewed destination minor.
  fromVersion = "19.3.3";
  toVersion = "19.4.1";

  upgradePathDocumentation = "https://docs.gitlab.com/update/upgrade_paths/";
  releaseNotes = "https://docs.gitlab.com/update/versions/gitlab_19_changes/";
}
