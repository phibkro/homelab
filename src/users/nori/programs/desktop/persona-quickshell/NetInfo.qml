pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

/*
 * Persona upstream shells out to nmcli and therefore requires NetworkManager.
 * This workstation uses the NixOS DHCP backend. Preserve Persona's public
 * network model while sourcing active links from iproute2 instead.
 */
Singleton {
    id: root

    readonly property list<AccessPoint> networks: []
    readonly property AccessPoint active: networks.find(network => network.active) ?? null
    readonly property bool wifiEnabled: active !== null
    readonly property bool scanning: query.running
    readonly property bool connected: active !== null
    readonly property string networkName: active?.ssid ?? "Not Connected"
    readonly property int networkStrength: active?.strength ?? 0
    readonly property string wifiStatus: connected ? "connected" : "disconnected"

    function toggleWifi(): void {
        update();
    }

    function rescanWifi(): void {
        update();
    }

    function scanNetworks(): void {
        update();
    }

    function update(): void {
        if (!query.running)
            query.running = true;
    }

    function reconcile(fresh): void {
        const stale = networks.filter(current => !fresh.find(candidate => candidate.bssid === current.bssid));
        for (const network of stale)
            networks.splice(networks.indexOf(network), 1).forEach(object => object.destroy());

        for (const network of fresh) {
            const current = networks.find(candidate => candidate.bssid === network.bssid);
            if (current)
                current.lastIpcObject = network;
            else
                networks.push(accessPointComponent.createObject(root, { lastIpcObject: network }));
        }
    }

    Process {
        id: query
        command: ["ip", "-j", "address", "show", "up"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const links = JSON.parse(text);
                    const physicalLinks = links.filter(link =>
                        link.ifname !== "lo"
                            && link.link_type === "ether"
                            && link.linkinfo === undefined);
                    root.reconcile(physicalLinks.map(link => ({
                        active: true,
                        strength: 0,
                        frequency: 0,
                        ssid: link.ifname,
                        bssid: link.ifname,
                        security: ""
                    })));
                } catch (error) {
                    console.warn("persona network query failed:", error);
                }
            }
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.update()
    }

    component AccessPoint: QtObject {
        required property var lastIpcObject
        readonly property string ssid: lastIpcObject.ssid
        readonly property string bssid: lastIpcObject.bssid
        readonly property int strength: lastIpcObject.strength
        readonly property int frequency: lastIpcObject.frequency
        readonly property bool active: lastIpcObject.active
        readonly property string security: lastIpcObject.security
        readonly property bool isSecure: false
    }

    Component {
        id: accessPointComponent
        AccessPoint {}
    }
}
