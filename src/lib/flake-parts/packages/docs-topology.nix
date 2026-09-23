/*
  Generated topology reference from the public inventory values and the
  canonical `nori.inventory.hosts` option schema.

  Build:      nix build .#docs-topology
  Output:     ./result (CommonMark file)
  Committed:  docs/generated/topology.md
*/
{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    let
      eval = inputs.self.nixosConfigurations.workstation;
      helpers = import ../../nixdoc.nix { inherit pkgs lib eval; };
    in
    {
      packages.docs-topology =
        let
          hosts = inputs.self.lib.noriInventory.hosts;
          hostNames = lib.attrNames hosts;
          nixosHostNames = lib.attrNames (lib.filterAttrs (_: host: host.kind == "nixos") hosts);
          renderJob = job: lib.replaceStrings [ "\n" ] [ " " ] (lib.strings.trim job);
          renderRoleCell =
            host: if host.roleOneLiner == "" then "`${host.role}`" else "`${host.role}` (${host.roleOneLiner})";
          hostRow =
            name:
            let
              h = hosts.${name};
            in
            "| **${name}** | `${h.kind}` | ${h.codename} | ${renderRoleCell h} | `${h.tailnetIp}` | ${
              if h.lanIp == null then "—" else "`${h.lanIp}`"
            } | ${h.hardware} | ${renderJob h.primaryJob} |";
          hostsTable = lib.concatStringsSep "\n" (
            [
              "| Host | Managed by | Codename | Role | Tailnet | LAN | Hardware | Primary job |"
              "|---|---|---|---|---|---|---|---|"
            ]
            ++ map hostRow hostNames
          );
          isHostsOption =
            opt:
            let
              inherit (opt) loc;
              prefix = builtins.head loc;
              second = if builtins.length loc >= 2 then builtins.elemAt loc 1 else "";
              third = if builtins.length loc >= 3 then builtins.elemAt loc 2 else "";
            in
            prefix == "nori" && second == "inventory" && third == "hosts";
          optionsDoc = helpers.mkOptionsDoc isHostsOption;
          inventoryDoc = helpers.mkNixdocSection {
            file = ../../../infra/common/nixos/inventory.nix;
            description = "Inventory host registry — overview";
            category = "inventory-hosts";
          };
          hostHardwareDoc = name: helpers.mkFileDocstring (../../.. + "/infra/${name}/hardware.nix");
          hardwareSection = pkgs.runCommandLocal "hardware-section" { } (
            lib.concatStringsSep "\n" (
              [
                "cat <<'HEADER' > $out"
                "## Per-host hardware posture"
                ""
                "HEADER"
              ]
              ++ map (name: "cat ${hostHardwareDoc name} >> $out") nixosHostNames
            )
          );
        in
        pkgs.runCommandLocal "docs-topology"
          {
            nativeBuildInputs = [ pkgs.gnused ];
          }
          ''
            cat > $out <<'HEADER'
            ---
            generated: true
            source: flake.nix § packages.docs-topology
            regenerate: nix build .#docs-topology
            ---

            # Topology — generated reference

            Auto-derived from the `nori.inventory.hosts` schema + values in
            `src/inventory/hosts.nix`. Do not hand-edit; the hand-curated overview
            lives at `docs/reference/topology.md` (kept parallel for the
            generated-vs-handwritten coverage experiment).

            HEADER
            cat ${inventoryDoc} >> $out
            echo >> $out
            cat ${hardwareSection} >> $out
            echo >> $out
            cat >> $out <<'GLANCE_HEADER'

            ## Hosts at a glance

            GLANCE_HEADER
            cat >> $out <<'TABLE'
            ${hostsTable}
            TABLE
            cat >> $out <<'SCHEMA_HEADER'

            ## Registry schema (`nori.inventory.hosts.<name>.*`)

            What an `src/inventory/hosts.nix` identity entry must declare to
            satisfy the schema. Schema lives in `src/infra/common/nixos/inventory.nix`.

            SCHEMA_HEADER
            # Normalize nixosOptionsDoc output to plain GFM.
            sed -e 's/\\\([.<>()]\)/\1/g' \
                -e 's|\[\([^]]*\)\](file://[^)]*)|`\1`|g' \
                ${optionsDoc.optionsCommonMark} >> $out
          '';
    };
}
