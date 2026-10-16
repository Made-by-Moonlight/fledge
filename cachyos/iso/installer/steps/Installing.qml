import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"

// The install's progress, then what to do next. Return (Frame) and `next` over
// IPC run Installer.primary(), the highlighted button of whichever outcome shows.
Column {
    id: page
    spacing: 16
    width: 680
    property bool showLog: false
    property int secs: 10
    property bool cancelled: false
    Title {
        text: Run.state === "done" ? "Installed" : Run.state === "running" ? "Installing fledge"
            : Run.state === "desktopFailed" ? "Installed, but the desktop setup failed" : "The install failed"
        sub: Run.state === "running" ? "This takes a while. You can leave it." : Run.state === "idle" ? "" : "Return does the highlighted action."
    }
    Repeater {
        model: Run.stages
        delegate: Row {
            required property var modelData
            readonly property string st: Run.stageState(modelData[0])
            spacing: 12
            Glyph {
                width: 18
                text: parent.st === "done" ? "󰄬" : parent.st === "running" ? "󰔟" : parent.st === "failed" ? "󰅖" : "·"
                color: parent.st === "failed" ? Theme.error : parent.st === "waiting" ? Theme.muted : Theme.accent
            }
            Glyph {
                text: modelData[1] + (parent.st === "running" && Run.m > 0 ? "   " + Run.n + " / " + Run.m + " packages" : "")
                color: parent.st === "waiting" ? Theme.muted : Theme.fg
            }
        }
    }
    Rectangle {
        width: page.width; height: 8; radius: 4; color: Theme.bgRaised
        Rectangle {
            width: parent.width * Run.progress; height: parent.height; radius: 4
            color: Run.state === "failed" ? Theme.error : Theme.accent
            Behavior on width { NumberAnimation { duration: 300 } }
        }
    }

    // Done
    Column {
        visible: Run.state === "done"; spacing: 12
        Glyph { text: "Remove the USB stick, then reboot. Unlock the disk and log in to fledge."; color: Theme.fgDim }
        Row {
            spacing: 10
            Button { primary: true; text: "Reboot now"; onClicked: Installer.primary() }
            Button { text: "Stay here"; visible: !page.cancelled; onClicked: page.cancelled = true }
        }
        Glyph { visible: !page.cancelled; text: "Rebooting in " + page.secs + " s"; color: Theme.muted }
    }
    Timer {
        interval: 1000; repeat: true
        running: Run.state === "done" && !page.cancelled
        onTriggered: { page.secs -= 1; if (page.secs <= 0) Run.reboot(); }
    }

    // Failed in a base stage: the disk is half-written, start over.
    Row {
        visible: Run.state === "failed"; spacing: 10
        Button { primary: true; text: "Clean up and start over"; onClicked: Installer.primary() }
        Button { text: "Open terminal"; onClicked: Installer.openTerminal() }
    }
    // Failed in Desktop: the system is installed and firstboot can finish it.
    Column {
        visible: Run.state === "desktopFailed"; spacing: 12
        Glyph {
            width: page.width; wrapMode: Text.WordWrap; color: Theme.fgDim
            text: "The system is installed. Retry the desktop setup, or reboot and it finishes on the first boot."
        }
        Row {
            spacing: 10
            Button { primary: true; text: "Retry desktop"; onClicked: Installer.primary() }
            Button { text: "Reboot anyway"; onClicked: Run.cleanup(() => Run.reboot()) }
            Button { text: "Open terminal"; onClicked: Installer.openTerminal() }
        }
    }

    Button {
        visible: Run.state === "running" || Run.state === "done"
        text: page.showLog ? "Hide log" : "Show log"
        onClicked: page.showLog = !page.showLog
    }
    Rectangle {
        visible: page.showLog || Run.state === "failed" || Run.state === "desktopFailed"
        width: page.width; height: 260; radius: Theme.radius; color: Theme.bgRaised; clip: true
        ListView {
            id: logView
            anchors { fill: parent; margins: 10 }
            model: Run.state === "running" || Run.state === "done" ? Run.log : Run.log.slice(-20)
            delegate: Glyph {
                required property var modelData
                width: logView.width; text: modelData; font.pixelSize: Theme.fontSmall; color: Theme.fgDim; elide: Text.ElideRight
            }
            onCountChanged: positionViewAtEnd()
        }
    }
}
