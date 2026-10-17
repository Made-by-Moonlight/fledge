import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import "../theme"
import "../services"
import "../components"

Pill {
    id: card
    required property var notification
    property bool popup: false
    width: 360
    height: content.implicitHeight + 20
    border.color: notification.urgency === NotificationUrgency.Critical ? Theme.error : Theme.surface

    Rectangle { width: 3; height: parent.height - 16; radius: 2; color: Theme.accent; anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter }

    Column {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; leftMargin: 18 }
        spacing: 3
        Row {
            spacing: 6
            width: parent.width
            Glyph { text: card.notification.appName || "notification"; font.bold: true; font.pixelSize: Theme.fontSmall }
            Glyph { text: "· now"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
        }
        Glyph { width: parent.width; text: card.notification.summary; wrapMode: Text.Wrap; font.bold: true }
        Glyph { width: parent.width; visible: text !== ""; text: Notifs.sanitize(card.notification.body); color: Theme.fgDim; wrapMode: Text.Wrap; textFormat: Text.StyledText; maximumLineCount: 4; elide: Text.ElideRight }
        Row {
            spacing: 6
            visible: card.notification.actions.length > 0
            Repeater {
                model: card.notification.actions
                delegate: Pill {
                    required property var modelData
                    color: Theme.surface; height: 24; width: lbl.implicitWidth + 16
                    Glyph { id: lbl; anchors.centerIn: parent; text: parent.modelData.text; font.pixelSize: Theme.fontSmall }
                    MouseArea { anchors.fill: parent; onClicked: parent.modelData.invoke() }
                }
            }
        }
    }

    Glyph { text: "󰅖"; color: Theme.muted; anchors { top: parent.top; right: parent.right; margins: 8 }
        MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: Notifs.dismiss(card.notification) } }

    // The card body: run the default action, then dismiss.
    MouseArea {
        anchors.fill: parent; z: -1
        onClicked: Notifs.invokeDefault(card.notification)
    }

    // Expiry is owned by Notifs (per-notification deadlines), so re-created cards keep their countdown.
    Connections { target: card.notification; function onClosed() { Notifs.unpop(card.notification); } }
}
