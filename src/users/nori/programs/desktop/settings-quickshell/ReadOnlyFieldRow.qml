pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    required property var client
    required property string componentId
    required property string fieldKey
    required property var presentation

    readonly property var resolved: root.client.resolvedValue(root.componentId, root.fieldKey)

    Layout.fillWidth: true
    implicitHeight: contents.implicitHeight + 28
    radius: 10
    color: "#20242f"
    border.width: 1
    border.color: "#3b4252"

    ColumnLayout {
        id: contents

        anchors {
            fill: parent
            margins: 14
        }
        spacing: 7

        RowLayout {
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: root.presentation.title || root.fieldKey
                font.weight: Font.DemiBold
                color: "#dce3f7"
                elide: Text.ElideRight
            }
            Label {
                text: "Authored policy"
                color: "#aab4ca"
                font.pixelSize: 12
            }
        }

        Label {
            Layout.fillWidth: true
            text: root.presentation.description || ""
            visible: Boolean(root.presentation.description)
            color: "#c4cad9"
            wrapMode: Text.Wrap
        }

        Label {
            Layout.fillWidth: true
            text: root.presentation.reason || "This field is managed by authored policy."
            color: "#ffdb8b"
            wrapMode: Text.Wrap
        }

        Label {
            Layout.fillWidth: true
            text: "Resolved: " + root.client.displayValue(root.resolved)
            color: "#e6eaff"
            wrapMode: Text.WrapAnywhere
        }
    }
}
