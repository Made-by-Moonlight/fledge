import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../components"

// The approved made by moonlight lock (was dot-config/hypr/hyprlock.conf): glow background,
// clock, owl, wordmark, amber dots field. hyprlock offsets are from the centre with y up;
// here y points down, and its point sizes are ×4/3 in pixels.
WlSessionLockSurface {
    id: surface
    required property var lockRoot
    color: Theme.bg

    Image { anchors.fill: parent; source: "file://" + Theme.assets + "/glow.png"; fillMode: Image.PreserveAspectCrop }
    SystemClock { id: clock; precision: SystemClock.Minutes }

    // The design is laid out for an 800 px tall screen; shorter ones (e.g. 1080p at 1.5x)
    // scale it down rather than cut the clock off.
    Item {
        anchors.centerIn: parent
        width: parent.width; height: parent.height
        scale: Math.min(1, surface.height / 760)

        Glyph {
            text: Qt.formatDateTime(clock.date, "HH:mm"); font.pixelSize: 128
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: -300 }
        }
        // The owl's visual centre (between the eyes) is 61.7% across: shift it onto the axis.
        Image {
            source: "file://" + Theme.assets + "/owl.png"; width: 260; height: 260; fillMode: Image.PreserveAspectFit
            sourceSize.width: 260
            anchors { horizontalCenter: parent.horizontalCenter; horizontalCenterOffset: -30; verticalCenter: parent.verticalCenter; verticalCenterOffset: -70 }
        }
        // The distro's wordmark, with the org as a muted byline (as the installer has it).
        Glyph {
            text: "f l e d g e"; font.pixelSize: 23
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: 100 }
        }
        Glyph {
            text: "made by moonlight"; font.pixelSize: 15; color: Theme.muted
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: 132 }
        }

        Rectangle {
            id: field
            width: 420; height: 64
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: 190 }
            color: Theme.bgRaised
            border.color: surface.lockRoot.status === "failed" ? Theme.error : Theme.surface
            border.width: 2
            clip: true
            Row {
                anchors.centerIn: parent; spacing: 4
                Repeater { model: surface.lockRoot.typed; delegate: Rectangle { width: 8; height: 8; radius: 4; color: Theme.accent } }
            }
            Glyph {
                anchors.centerIn: parent
                width: parent.width - 24
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: surface.lockRoot.typed === 0 && surface.lockRoot.status !== ""
                text: surface.lockRoot.status === "checking" ? "…"
                    : (surface.lockRoot.note ? "failed" : "wrong password") + " (" + surface.lockRoot.attempts + ")"
                color: surface.lockRoot.status === "failed" ? Theme.error : Theme.muted
                font.italic: true
            }
        }
        // PAM's own text (faillock's lockout notice, "too many attempts" …) under the field:
        // wrapped so it isn't cut off, and plain text so a module's message can't inject markup.
        Glyph {
            anchors { horizontalCenter: parent.horizontalCenter; top: field.bottom; topMargin: 14 }
            width: 560
            visible: surface.lockRoot.note !== "" && surface.lockRoot.typed === 0
            text: surface.lockRoot.note
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: Theme.error
            font.italic: true
        }
    }

    // Keystrokes go straight to Lock; no TextInput holds a copy of the password.
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            const r = surface.lockRoot;
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) r.submit();
            else if (e.key === Qt.Key_Backspace) r.backspace();
            else if (e.key === Qt.Key_Escape || (e.key === Qt.Key_U && e.modifiers & Qt.ControlModifier)) r.clear();
            else if (e.text.length > 0 && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier)) && !/[\x00-\x1f\x7f]/.test(e.text)) r.type(e.text);
            e.accepted = true;
        }
    }
}
