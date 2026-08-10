pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland

/*
 * Native notification daemon for the Persona shell.
 *
 * Normal notifications reuse Persona's angled navy/cyan cards and stack below
 * its top-right clock. The rice's layer-osd messages keep their centered,
 * short-lived presentation. Notifications are deliberately transient: there is
 * no history store, and Mako must not run beside this D-Bus server.
 */
Scope {
    id: root

    readonly property int maxVisible: 5
    readonly property string layerOsdAppName: "layer-osd"
    readonly property var normalNotifications: server.trackedNotifications.values.filter(notification => notification.appName !== layerOsdAppName)
    readonly property var layerNotifications: server.trackedNotifications.values.filter(notification => notification.appName === layerOsdAppName)
    readonly property var layerNotification: layerNotifications.length > 0 ? layerNotifications[layerNotifications.length - 1] : null

    NotificationServer {
        id: server
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: false
        persistenceSupported: false
        keepOnReload: true

        onNotification: notification => {
            const tracked = server.trackedNotifications.values.filter(current => current !== notification);
            if (notification.appName === root.layerOsdAppName) {
                tracked.filter(current => current.appName === root.layerOsdAppName).forEach(current => current.expire());
            } else {
                const normal = tracked.filter(current => current.appName !== root.layerOsdAppName);
                if (normal.length >= root.maxVisible) {
                    const evictable = normal.find(current =>
                        !current.resident && current.urgency !== NotificationUrgency.Critical);
                    if (evictable) {
                        evictable.expire();
                    } else if (!notification.resident && notification.urgency !== NotificationUrgency.Critical) {
                        return;
                    }
                }
            }
            notification.tracked = true;
        }
    }

    PanelWindow {
        id: notificationWindow
        visible: root.normalNotifications.length > 0
        color: "transparent"
        implicitWidth: 460
        implicitHeight: Math.max(1, notificationStack.implicitHeight)
        focusable: false

        anchors {
            top: true
            right: true
        }
        margins.top: 220
        margins.right: 20

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "persona.notifications"

        Column {
            id: notificationStack
            width: parent.width
            spacing: 12

            Repeater {
                model: server.trackedNotifications

                ToastCard {
                    required property var modelData
                    notification: modelData
                }
            }
        }
    }

    PanelWindow {
        id: layerOsdWindow
        visible: root.layerNotification !== null
        color: "transparent"
        implicitWidth: 280
        implicitHeight: 96
        focusable: false
        mask: Region {}

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "persona.layer-osd"

        Loader {
            anchors.centerIn: parent
            active: root.layerNotification !== null
            sourceComponent: LayerOsdCard {
                notification: root.layerNotification
            }
        }
    }

    component ToastCard: Item {
        id: card

        required property var notification
        readonly property bool hasNotification: notification !== null && notification !== undefined
        readonly property bool isNormal: hasNotification && notification.appName !== root.layerOsdAppName
        readonly property bool isPresented: isNormal
            && root.normalNotifications.slice(-root.maxVisible).includes(notification)
        readonly property color accent: !hasNotification
            ? "#9cf7ff"
            : notification.urgency === NotificationUrgency.Critical
                ? "#ffe500"
                : notification.urgency === NotificationUrgency.Low ? "#5c5f70" : "#9cf7ff"
        // Quickshell 0.3 passes the D-Bus millisecond value through unchanged.
        readonly property int requestedTimeout: hasNotification && notification.expireTimeout > 0
            ? Math.round(notification.expireTimeout)
            : 5000
        readonly property bool shouldExpire: hasNotification
            && isPresented
            && !notification.resident
            && notification.urgency !== NotificationUrgency.Critical
            && notification.expireTimeout !== 0
        readonly property int cardHeight: Math.max(112, content.implicitHeight + 30)

        width: 460
        height: isPresented ? cardHeight : 0
        visible: isPresented
        x: 40
        opacity: 0

        function resetPresentation(): void {
            expiryTimer.stop();
            if (!card.isPresented)
                return;
            card.x = 40;
            card.opacity = 0;
            enterAnimation.restart();
            if (card.shouldExpire)
                expiryTimer.start();
            cardShape.requestPaint();
        }

        Component.onCompleted: resetPresentation()
        onIsPresentedChanged: resetPresentation()
        onAccentChanged: cardShape.requestPaint()

        ParallelAnimation {
            id: enterAnimation
            NumberAnimation {
                target: card
                property: "x"
                to: 0
                duration: 250
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: card
                property: "opacity"
                to: 1
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Timer {
            id: expiryTimer
            interval: card.requestedTimeout
            repeat: false
            running: false
            onTriggered: {
                if (card.hasNotification)
                    card.notification.expire();
            }
        }

        Connections {
            target: card.hasNotification ? card.notification : null

            function onAppNameChanged() {
                card.resetPresentation();
            }
            function onBodyChanged() {
                card.resetPresentation();
            }
            function onExpireTimeoutChanged() {
                card.resetPresentation();
            }
            function onResidentChanged() {
                card.resetPresentation();
            }
            function onSummaryChanged() {
                card.resetPresentation();
            }
            function onUrgencyChanged() {
                card.resetPresentation();
            }
        }

        Canvas {
            id: cardShape
            anchors.fill: parent

            onPaint: {
                const context = getContext("2d");
                context.clearRect(0, 0, width, height);

                context.beginPath();
                context.moveTo(0, 0);
                context.lineTo(width - 18, 0);
                context.lineTo(width, height);
                context.lineTo(18, height);
                context.closePath();
                context.fillStyle = card.accent;
                context.fill();

                context.beginPath();
                context.moveTo(3, 3);
                context.lineTo(width - 20, 3);
                context.lineTo(width - 3, height - 3);
                context.lineTo(20, height - 3);
                context.closePath();
                context.fillStyle = "#10185f";
                context.fill();
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        Rectangle {
            x: 8
            y: 16
            width: 48
            height: 58
            rotation: -8
            color: "#0c0f1d"
            border.color: card.accent
            border.width: 3

            Text {
                anchors.centerIn: parent
                text: !card.hasNotification
                    ? "?"
                    : card.notification.urgency === NotificationUrgency.Critical
                        ? "!"
                        : (card.notification.appName.length > 0 ? card.notification.appName.charAt(0).toUpperCase() : "?")
                color: card.accent
                font.family: "Montserrat"
                font.pixelSize: 24
                font.weight: Font.Bold
                rotation: 8
            }
        }

        Column {
            id: content
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 14
                leftMargin: 72
                rightMargin: 42
            }
            spacing: 5

            Text {
                width: parent.width
                text: card.hasNotification && card.notification.appName.length > 0 ? card.notification.appName.toUpperCase() : "SYSTEM"
                textFormat: Text.PlainText
                color: card.accent
                font.family: "JetBrainsMono Nerd Font Mono"
                font.pixelSize: 10
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: card.hasNotification ? card.notification.summary : ""
                textFormat: Text.PlainText
                visible: text.length > 0
                color: "#f6fbff"
                font.family: "Montserrat"
                font.pixelSize: 18
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: card.hasNotification ? card.notification.body : ""
                visible: text.length > 0
                color: "#c2c3c6"
                font.family: "Montserrat"
                font.pixelSize: 13
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }

            Flow {
                width: parent.width
                spacing: 8
                visible: card.hasNotification && card.notification.actions.length > 0

                Repeater {
                    model: card.hasNotification ? card.notification.actions : []

                    Rectangle {
                        id: actionButton
                        required property var modelData
                        visible: modelData !== null && modelData !== undefined && modelData.text.length > 0
                        width: visible ? actionLabel.implicitWidth + 22 : 0
                        height: visible ? 28 : 0
                        color: "#0c0f1d"
                        border.color: card.accent
                        border.width: 1

                        Text {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: actionButton.modelData?.text ?? ""
                            textFormat: Text.PlainText
                            color: card.accent
                            font.family: "JetBrainsMono Nerd Font Mono"
                            font.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (actionButton.modelData)
                                    actionButton.modelData.invoke();
                            }
                        }
                    }
                }
            }
        }

        Text {
            anchors {
                top: parent.top
                right: parent.right
                topMargin: 8
                rightMargin: 15
            }
            text: "×"
            color: card.accent
            font.family: "Montserrat"
            font.pixelSize: 22

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (card.hasNotification)
                        card.notification.dismiss();
                }
            }
        }
    }

    component LayerOsdCard: Item {
        id: osdCard

        required property var notification
        readonly property bool hasNotification: notification !== null && notification !== undefined
        property bool ready: false

        width: 260
        height: 76
        opacity: 0
        scale: 0.92

        function resetPresentation(): void {
            osdTimer.stop();
            if (!osdCard.hasNotification)
                return;
            osdCard.opacity = 0;
            osdCard.scale = 0.92;
            enterAnimation.restart();
            osdTimer.start();
        }

        Component.onCompleted: {
            ready = true;
            resetPresentation();
        }
        onNotificationChanged: {
            if (ready)
                resetPresentation();
        }

        ParallelAnimation {
            id: enterAnimation
            NumberAnimation {
                target: osdCard
                property: "opacity"
                to: 1
                duration: 120
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: osdCard
                property: "scale"
                to: 1
                duration: 180
                easing.type: Easing.OutBack
            }
        }

        Timer {
            id: osdTimer
            interval: 900
            repeat: false
            running: false
            onTriggered: {
                if (osdCard.hasNotification)
                    osdCard.notification.expire();
            }
        }

        Connections {
            target: osdCard.hasNotification ? osdCard.notification : null

            function onAppNameChanged() {
                osdCard.resetPresentation();
            }
            function onBodyChanged() {
                osdCard.resetPresentation();
            }
            function onSummaryChanged() {
                osdCard.resetPresentation();
            }
        }

        Canvas {
            anchors.fill: parent
            onPaint: {
                const context = getContext("2d");
                context.clearRect(0, 0, width, height);
                context.beginPath();
                context.moveTo(0, 0);
                context.lineTo(width - 16, 0);
                context.lineTo(width, height);
                context.lineTo(16, height);
                context.closePath();
                context.fillStyle = "#9cf7ff";
                context.fill();

                context.beginPath();
                context.moveTo(3, 3);
                context.lineTo(width - 18, 3);
                context.lineTo(width - 3, height - 3);
                context.lineTo(18, height - 3);
                context.closePath();
                context.fillStyle = "#10185f";
                context.fill();
            }
        }

        Rectangle {
            x: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            height: 48
            rotation: -8
            color: "#0c0f1d"
            border.color: "#9cf7ff"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "L"
                color: "#9cf7ff"
                font.family: "Montserrat"
                font.pixelSize: 20
                font.weight: Font.Bold
                rotation: 8
            }
        }

        Text {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 68
                rightMargin: 22
            }
            text: !osdCard.hasNotification
                ? ""
                : osdCard.notification.summary.length > 0 ? osdCard.notification.summary : osdCard.notification.body
            textFormat: Text.PlainText
            color: "#f6fbff"
            font.family: "Montserrat"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
