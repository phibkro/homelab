pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    required property var client
    required property string componentId
    required property string settingKey
    required property var presentation

    readonly property string control: root.presentation && root.presentation.control
        ? root.presentation.control
        : ""
    readonly property var desired: root.client.desiredValue(root.componentId, root.settingKey)
    readonly property var resolved: root.client.resolvedValue(root.componentId, root.settingKey)
    readonly property var enumChoices: root.client.enumValues(root.componentId, root.settingKey)
    readonly property string enumProblem: root.client.enumError(root.componentId, root.settingKey)
    readonly property bool enumSupported: root.control === "enum" && root.enumProblem.length === 0
    readonly property bool scalarSupported: root.control === "boolean"
        || root.control === "text"
        || root.control === "number"
        || root.control === "list"
    readonly property bool supported: root.enumSupported || root.scalarSupported
    readonly property string editorText: {
        if (root.control === "text")
            return typeof root.desired === "string" ? root.desired : "";
        if (root.desired === undefined || root.desired === null)
            return "";
        return JSON.stringify(root.desired);
    }

    Layout.fillWidth: true
    implicitHeight: contents.implicitHeight + 32
    radius: 10
    color: "#252936"
    border.width: 1
    border.color: root.supported ? "#3b4252" : "#be5f69"

    function enumIndex() {
        for (let index = 0; index < root.enumChoices.length; index += 1) {
            if (root.enumChoices[index] === root.desired)
                return index;
        }
        return -1;
    }

    function commitEditor(text) {
        const parsed = root.client.parseControlValue(root.control, text);
        if (!parsed.ok) {
            root.client.reportInputError("invalid_input", parsed.message, parsed.details);
            return;
        }

        if (JSON.stringify(parsed.value) !== JSON.stringify(root.desired))
            root.client.change(root.componentId, root.settingKey, parsed.value);
    }

    ColumnLayout {
        id: contents

        anchors {
            fill: parent
            margins: 16
        }
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: root.presentation.title || root.settingKey
                font.weight: Font.DemiBold
                font.pixelSize: 16
                color: "#f5f7ff"
                elide: Text.ElideRight
            }

            Label {
                text: root.control || "unknown"
                color: root.supported ? "#aab4ca" : "#ffb2b9"
                font.pixelSize: 12
            }
        }

        Label {
            Layout.fillWidth: true
            visible: Boolean(root.presentation.description)
            text: root.presentation.description || ""
            color: "#c4cad9"
            wrapMode: Text.Wrap
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 10
            rowSpacing: 6

            Repeater {
                model: [
                    { label: "Desired", value: root.client.displayValue(root.desired) },
                    { label: "Resolved", value: root.client.displayValue(root.resolved) },
                    { label: "Observed", value: root.client.observedDisplay(root.componentId, root.settingKey) }
                ]

                delegate: Rectangle {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredWidth: 220
                    implicitHeight: statusContent.implicitHeight + 12
                    radius: 6
                    color: "#1d202b"

                    ColumnLayout {
                        id: statusContent

                        anchors {
                            fill: parent
                            margins: 6
                        }
                        spacing: 2

                        Label {
                            text: modelData.label
                            color: "#98a2b8"
                            font.pixelSize: 11
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.value
                            color: "#e6eaff"
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }
        }

        ComboBox {
            id: enumEditor

            Layout.fillWidth: true
            visible: root.enumSupported
            enabled: !root.client.busy
            model: root.enumChoices
            currentIndex: root.enumIndex()
            onActivated: function(index) {
                const value = root.enumChoices[index];
                if (value !== root.desired)
                    root.client.change(root.componentId, root.settingKey, value);
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.enumSupported && root.desired !== undefined && root.enumIndex() < 0
            text: "The desired value is outside the generated enum. Choose one of the available values to repair it."
            color: "#ffb2b9"
            wrapMode: Text.Wrap
        }

        Switch {
            visible: root.control === "boolean"
            enabled: !root.client.busy
            text: checked ? "Enabled" : "Disabled"
            checked: Boolean(root.desired)
            onClicked: root.client.change(root.componentId, root.settingKey, checked)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.control === "text" || root.control === "number"
            spacing: 8

            TextField {
                id: scalarEditor

                Layout.fillWidth: true
                enabled: !root.client.busy
                text: root.editorText
                selectByMouse: true
                onAccepted: root.commitEditor(text)
            }

            Button {
                text: "Save"
                enabled: !root.client.busy
                onClicked: root.commitEditor(scalarEditor.text)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.control === "list"
            spacing: 8

            TextArea {
                id: listEditor

                Layout.fillWidth: true
                Layout.preferredHeight: 110
                enabled: !root.client.busy
                text: root.editorText
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
            }

            Button {
                Layout.alignment: Qt.AlignRight
                text: "Save JSON list"
                enabled: !root.client.busy
                onClicked: root.commitEditor(listEditor.text)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: !root.supported
            implicitHeight: unsupportedText.implicitHeight + 16
            radius: 6
            color: "#472b31"

            Label {
                id: unsupportedText

                anchors {
                    fill: parent
                    margins: 8
                }
                text: root.control === "enum" && root.enumProblem.length > 0
                    ? "Unsupported generated enum: " + root.enumProblem
                    : "Unsupported generated control '" + (root.control || "missing")
                        + "'. This client will not write an ambiguous value."
                color: "#ffd9dd"
                wrapMode: Text.Wrap
            }
        }
    }
}
