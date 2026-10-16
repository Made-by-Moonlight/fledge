import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

Flickable {
    id: page
    contentHeight: col.implicitHeight; clip: true
    // Edits collect here; Save writes them all and applies (input is generated config), so
    // nothing writes per keystroke. The draft is dropped once the write lands, and kept if
    // `check` refused it so the banner's complaint can be fixed in place.
    property var draft: ({})
    readonly property bool dirty: Object.keys(draft).length > 0
    function val(k, d) { return draft[k] !== undefined ? draft[k] : Settings.get("input", k, d); }
    function tp(k, d) { return draft["touchpad." + k] !== undefined ? draft["touchpad." + k] : (Settings.get("input", "touchpad", {})[k] ?? d); }
    function put(k, v) { const d = Object.assign({}, draft); d[k] = v; draft = d; }
    property bool saving: false
    Connections {
        target: Settings
        function onWriteFinished(ok, error) { if (page.saving) { page.saving = false; if (ok) page.draft = ({}); } }
    }

    RowLayout {
        id: col
        width: page.width; spacing: 32
        ColumnLayout {
            Layout.alignment: Qt.AlignTop; Layout.fillWidth: true; spacing: 14
            Field { Layout.fillWidth: true; label: "Keyboard layout (e.g. us, gb, us,de)"; text: page.val("kbLayout", "us"); onEdited: t => page.put("kbLayout", t) }
            Field { Layout.fillWidth: true; label: "Keyboard variant (xkb, e.g. dvorak; empty for default)"; text: page.val("kbVariant", ""); onEdited: t => page.put("kbVariant", t) }
            Field { Layout.fillWidth: true; label: "Keyboard options (xkb, e.g. compose:caps)"; text: page.val("kbOptions", ""); onEdited: t => page.put("kbOptions", t) }
            Stepper { label: "Key repeat rate"; value: page.val("repeatRate", 40); from: 1; to: 200; step: 5; suffix: " /s"; onChanged: v => page.put("repeatRate", v) }
            Stepper { label: "Key repeat delay"; value: page.val("repeatDelay", 600); from: 100; to: 2000; step: 50; suffix: " ms"; onChanged: v => page.put("repeatDelay", v) }
            Toggle { label: "Num Lock on at login"; checked: page.val("numlock", true); onToggled: c => page.put("numlock", c) }
        }
        ColumnLayout {
            Layout.alignment: Qt.AlignTop; Layout.fillWidth: true; spacing: 14
            Stepper { label: "Pointer sensitivity"; value: page.val("sensitivity", 0); from: -1; to: 1; step: 0.1; decimals: 1; onChanged: v => page.put("sensitivity", v) }
            Glyph { text: "Touchpad"; color: Theme.muted; font.pixelSize: Theme.fontSmall; topPadding: 6 }
            Toggle { label: "Natural scrolling"; checked: page.tp("naturalScroll", false); onToggled: c => page.put("touchpad.naturalScroll", c) }
            Toggle { label: "Tap to click"; checked: page.tp("tapToClick", true); onToggled: c => page.put("touchpad.tapToClick", c) }
            Stepper { label: "Scroll speed"; value: page.tp("scrollFactor", 1); from: 0.1; to: 3; step: 0.1; decimals: 1; suffix: "×"; onChanged: v => page.put("touchpad.scrollFactor", v) }
            Row {
                spacing: 8; topPadding: 10
                Button { text: "Save"; primary: true; enabled: page.dirty && !Settings.busy
                         onClicked: { page.saving = true; Settings.set(Object.keys(page.draft).map(k => [".input." + k, page.draft[k]]), true); } }
                Button { text: "Discard"; enabled: page.dirty; onClicked: page.draft = ({}) }
                Button { text: "Reset to defaults"; onClicked: { page.draft = ({}); Settings.reset([".input"], true); } }
            }
        }
    }
}
