# Production Pi DNS is owned by Ansible; Nix Blocky is a test adapter.
{
  kind = "service";
  hostRoles = [ "appliance" ];
  tags = [ "network-appliance" ];
}
