pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ShellRoot {
    id: root

    SettingsClient {
        id: settingsClient
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() {
            Qt.quit();
        }
    }

    ApplicationWindow {
        id: appWindow

        visible: true
        title: "Desktop Settings"
        width: 1080
        height: 760
        minimumWidth: 760
        minimumHeight: 560
        color: "#171a23"

        header: Rectangle {
            implicitHeight: headerContent.implicitHeight + 28
            color: "#20242f"
            border.width: 1
            border.color: "#343b4d"

            ColumnLayout {
                id: headerContent

                anchors {
                    fill: parent
                    margins: 14
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: "Desktop Settings"
                            color: "#f5f7ff"
                            font.pixelSize: 23
                            font.weight: Font.DemiBold
                        }
                        Label {
                            text: "Desired profile, resolved configuration, and observed active desktop state"
                            color: "#b9c2d6"
                            font.pixelSize: 13
                        }
                    }

                    BusyIndicator {
                        running: settingsClient.busy
                        visible: running
                    }

                    Button {
                        text: "Refresh"
                        enabled: !settingsClient.busy
                        onClicked: settingsClient.refresh()
                    }

                    Button {
                        text: "Apply"
                        enabled: !settingsClient.busy
                            && settingsClient.stateLoaded
                            && !settingsClient.hasDrafts
                        onClicked: settingsClient.apply()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Label {
                        text: "Desired revision: " + (settingsClient.revision === undefined
                            ? "not loaded"
                            : settingsClient.revision)
                        color: "#dce3f7"
                    }
                    Label {
                        Layout.fillWidth: true
                        text: "Observed active generation: " + settingsClient.activeGenerationDisplay()
                        color: "#dce3f7"
                        elide: Text.ElideRight
                    }
                }
            }
        }

        ScrollView {
            id: contentScroll

            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: contentScroll.availableWidth
                spacing: 14

                Item {
                    Layout.preferredHeight: 2
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    visible: settingsClient.busy
                    implicitHeight: progressText.implicitHeight + 20
                    radius: 8
                    color: "#27344b"

                    Label {
                        id: progressText

                        anchors {
                            fill: parent
                            margins: 10
                        }
                        text: settingsClient.progressMessage
                        color: "#dbe7ff"
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    visible: settingsClient.error !== null
                    implicitHeight: errorContent.implicitHeight + 22
                    radius: 8
                    color: "#4d2830"
                    border.width: 1
                    border.color: "#c96773"

                    ColumnLayout {
                        id: errorContent

                        anchors {
                            fill: parent
                            margins: 11
                        }
                        spacing: 7

                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                text: settingsClient.error ? settingsClient.error.code : "request_failed"
                                color: "#ffd9dd"
                                font.weight: Font.DemiBold
                            }

                            Button {
                                visible: settingsClient.error
                                    && settingsClient.error.code === "revision_conflict"
                                text: "Reload current revision"
                                enabled: !settingsClient.busy
                                onClicked: settingsClient.reloadAfterConflict()
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: settingsClient.error ? settingsClient.error.message : ""
                            color: "#fff0f1"
                            wrapMode: Text.Wrap
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: settingsClient.error
                                && settingsClient.detailsText(settingsClient.error.details).length > 0
                            text: settingsClient.error
                                ? settingsClient.detailsText(settingsClient.error.details)
                                : ""
                            color: "#ffd9dd"
                            font.family: "monospace"
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }

                Rectangle {
                    id: pendingPreviewCard

                    readonly property var pending: settingsClient.pendingPreview
                    readonly property var preview: pending ? pending.preview : ({})

                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    visible: pending !== null
                    implicitHeight: previewContent.implicitHeight + 24
                    radius: 10
                    color: "#263446"
                    border.width: 1
                    border.color: "#7190bb"

                    ColumnLayout {
                        id: previewContent

                        anchors {
                            fill: parent
                            margins: 12
                        }
                        spacing: 8

                        Label {
                            Layout.fillWidth: true
                            text: pending
                                ? "Preview: " + pending.componentId + " / " + pending.settingKey
                                : ""
                            color: "#eef4ff"
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            wrapMode: Text.Wrap
                        }

                        Label {
                            Layout.fillWidth: true
                            text: pending
                                ? "Draft value: " + settingsClient.displayValue(pending.value)
                                    + " · profile revision " + pending.revision
                                : ""
                            color: "#d4e1fa"
                            wrapMode: Text.Wrap
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: preview.profileHash !== undefined
                            text: "Candidate profile hash: " + preview.profileHash
                            color: "#b8c9e8"
                            wrapMode: Text.WrapAnywhere
                        }

                        Label {
                            Layout.fillWidth: true
                            text: "Resolved candidate"
                            color: "#e6eaff"
                            font.weight: Font.DemiBold
                        }

                        Label {
                            Layout.fillWidth: true
                            text: settingsClient.detailsText(preview.resolved)
                            color: "#d4e1fa"
                            font.family: "monospace"
                            wrapMode: Text.WrapAnywhere
                        }

                        Label {
                            Layout.fillWidth: true
                            text: "Impact"
                            color: "#e6eaff"
                            font.weight: Font.DemiBold
                        }

                        Label {
                            Layout.fillWidth: true
                            text: settingsClient.detailsText(preview.impact)
                            color: "#d4e1fa"
                            font.family: "monospace"
                            wrapMode: Text.WrapAnywhere
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: !settingsClient.previewMatchesCurrent()
                            text: "This preview is stale. Edit or preview the draft again before saving it."
                            color: "#ffdb8b"
                            wrapMode: Text.Wrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Item {
                                Layout.fillWidth: true
                            }

                            Button {
                                text: "Discard preview"
                                enabled: !settingsClient.busy
                                onClicked: settingsClient.discardPreview()
                            }

                            Button {
                                text: "Save desired change"
                                enabled: !settingsClient.busy
                                    && settingsClient.previewMatchesCurrent()
                                onClicked: settingsClient.commitPreview()
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    visible: settingsClient.stateLoaded && !settingsClient.schemaLoaded
                    implicitHeight: schemaText.implicitHeight + 20
                    radius: 8
                    color: "#4d4026"
                    border.width: 1
                    border.color: "#c8a55c"

                    Label {
                        id: schemaText

                        anchors {
                            fill: parent
                            margins: 10
                        }
                        text: settingsClient.schemaError
                        color: "#ffedbd"
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    visible: settingsClient.jobRows().length > 0
                    implicitHeight: jobsContent.implicitHeight + 28
                    radius: 10
                    color: "#20242f"
                    border.width: 1
                    border.color: "#343b4d"

                    ColumnLayout {
                        id: jobsContent

                        anchors {
                            fill: parent
                            margins: 14
                        }
                        spacing: 9

                        Label {
                            text: "Build and activation jobs"
                            color: "#f5f7ff"
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: settingsClient.jobRows()

                            delegate: Rectangle {
                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: jobContent.implicitHeight + 18
                                radius: 7
                                color: "#1a1e28"

                                ColumnLayout {
                                    id: jobContent

                                    anchors {
                                        fill: parent
                                        margins: 9
                                    }
                                    spacing: 4

                                    Label {
                                        Layout.fillWidth: true
                                        text: "Job " + (modelData.id || "unknown")
                                            + " · " + settingsClient.jobStatus(modelData)
                                        color: "#e6eaff"
                                        font.weight: Font.DemiBold
                                        wrapMode: Text.Wrap
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: {
                                            switch (settingsClient.jobStatus(modelData)) {
                                            case "queued":
                                                return "Queued for build";
                                            case "building":
                                                return "Build in progress";
                                            case "activating":
                                                return "Activation in progress";
                                            case "reconciling":
                                                return "Reconciling the active generation and observed desktop state";
                                            case "active":
                                                return "Activated and reconciled";
                                            case "failed":
                                                return "Build or activation failed";
                                            case "interrupted":
                                                return "Interrupted before completion";
                                            default:
                                                return "Job progress not reported";
                                            }
                                        }
                                        color: "#c4cad9"
                                        wrapMode: Text.Wrap
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        visible: modelData.revision !== undefined
                                        text: "Profile revision: " + modelData.revision
                                        color: "#aab4ca"
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        visible: Boolean(modelData.activeGeneration)
                                        text: "Active generation: " + settingsClient.displayValue(modelData.activeGeneration)
                                        color: "#aab4ca"
                                        wrapMode: Text.WrapAnywhere
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: "Observed: " + settingsClient.jobObservation(modelData)
                                        color: "#aab4ca"
                                        wrapMode: Text.WrapAnywhere
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        visible: Boolean(modelData.error)
                                        text: modelData.error
                                            ? modelData.error.code + ": " + modelData.error.message
                                            : ""
                                        color: "#ffb2b9"
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    visible: settingsClient.stateLoaded && settingsClient.componentIds.length === 0
                    text: "The current profile has no generated desktop components."
                    color: "#c4cad9"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                Repeater {
                    model: settingsClient.componentIds

                    delegate: Rectangle {
                        id: componentCard
                        required property string modelData

                        readonly property string componentId: modelData
                        readonly property var componentModel: settingsClient.component(componentId)
                        readonly property var groups: settingsClient.groupRows(componentModel)
                        readonly property var readOnlyFields: settingsClient.readOnlyRows(componentModel)

                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        implicitHeight: componentContent.implicitHeight + 30
                        radius: 12
                        color: "#20242f"
                        border.width: 1
                        border.color: "#3b4252"

                        ColumnLayout {
                            id: componentContent

                            anchors {
                                fill: parent
                                margins: 15
                            }
                            spacing: 12

                            Label {
                                Layout.fillWidth: true
                                text: componentModel.title || componentId
                                color: "#f5f7ff"
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: Boolean(componentModel.description)
                                text: componentModel.description || ""
                                color: "#c4cad9"
                                wrapMode: Text.Wrap
                            }

                            Repeater {
                                model: groups

                                delegate: ColumnLayout {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: 8

                                    Label {
                                        text: modelData.name
                                        color: "#dce3f7"
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                    }

                                    Repeater {
                                        model: modelData.settings

                                        delegate: SettingRow {
                                            required property var modelData

                                            client: settingsClient
                                            componentId: componentCard.componentId
                                            settingKey: modelData.key
                                            presentation: modelData.presentation
                                        }
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: readOnlyFields.length > 0
                                text: "Authored read-only fields"
                                color: "#dce3f7"
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: readOnlyFields

                                delegate: ReadOnlyFieldRow {
                                    required property var modelData

                                    client: settingsClient
                                    componentId: componentCard.componentId
                                    fieldKey: modelData.key
                                    presentation: modelData.presentation
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.preferredHeight: 14
                }
            }
        }
    }
}
