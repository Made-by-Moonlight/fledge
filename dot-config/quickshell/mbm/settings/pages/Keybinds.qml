import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"
import ".."

Item {
    id: page
    property string filter: ""
    property string recording: ""          // id being re-recorded, or "new"
    property var draft: null               // new bind being added: {label, kind, value}

    function combo(b) { return (b.mods ? b.mods.split(" ").filter(m => m).join(" + ") + " + " : "") + b.key; }
    // Same identity the CLI uses for a clash: mods in any order, key case-insensitive, flags minus `d`.
    function norm(b) { return (b.mods ?? "").split(" ").filter(m => m).map(m => m.toUpperCase()).sort().join("+") + "+" + b.key.toLowerCase() + "/" + (b.flags ?? "").replace("d", "").split("").sort().join(""); }
    // Defaults overlaid per id with the user's binds (null removes one), not the validated merged
    // state: that is only written when `check` passes, so it can never show a clash.
    readonly property var effective: {
        const out = Object.assign({}, Settings.defaults.binds ?? {}), u = Settings.user?.binds ?? {};
        for (const id of Object.keys(u)) {
            if (u[id] === null) delete out[id];
            else out[id] = Object.assign({}, out[id] ?? {}, u[id]);
        }
        return out;
    }
    readonly property var all: Object.keys(effective).filter(id => effective[id]).map(id => Object.assign({ id }, effective[id]))
    readonly property var byCombo: { const m = {}; for (const b of all) (m[norm(b)] = m[norm(b)] ?? []).push(b); return m; }
    readonly property var rows: all
        .filter(b => !filter || (b.label + " " + combo(b) + " " + b.group).toLowerCase().includes(filter.toLowerCase()))
        .sort((a, b) => a.group.localeCompare(b.group) || a.label.localeCompare(b.label))
    function clashWith(b) { return (byCombo[norm(b)] ?? []).filter(o => o.id !== b.id).map(o => o.label); }
    function edited(id) { return Settings.user?.binds?.[id] !== undefined; }
    function path(id) { return '.binds["' + id + '"]'; }
    function nextCustomId() {
        let n = 0;
        for (const id of Object.keys(page.effective)) { const m = /^custom\.(\d+)$/.exec(id); if (m) n = Math.max(n, +m[1]); }
        for (const id of Object.keys(Settings.user?.binds ?? {})) { const m = /^custom\.(\d+)$/.exec(id); if (m) n = Math.max(n, +m[1]); }
        return "custom." + (n + 1);
    }

    function startRecording(id) { recording = id; recorder.start(); }

    KeyRecorder {
        id: recorder
        onRecorded: (mods, key) => {
            if (page.recording === "new") {
                const d = page.draft, action = d.kind === "exec" ? { exec: d.value } : d.kind === "shell" ? { shell: d.value } : { dispatch: d.value };
                Settings.set([[page.path(page.nextCustomId()), { mods, key, label: d.label.replace(/,/g, ""), group: "Custom", action }]], true);
                page.draft = null;
            } else {
                Settings.set([[page.path(page.recording) + ".mods", mods], [page.path(page.recording) + ".key", key]], true);
            }
            page.recording = "";
        }
        onCancelled: page.recording = ""
        onRefused: reason => { page.recording = ""; Settings.lastError = reason; }
        onUnavailable: { page.recording = ""; Settings.lastError = "Key recording isn't available: Hyprland has no mbm-record submap (run mbm settings apply)."; }
    }
    // The request may arrive before this page exists (settings.record opens the window first).
    function takeRequest() { if (ShellState.recordRequest) { const id = ShellState.recordRequest; ShellState.recordRequest = ""; startRecording(id); } }
    Component.onCompleted: takeRequest()
    Connections {
        target: ShellState
        function onRecordRequestChanged() { page.takeRequest(); }
        function onSettingsOpenChanged() { if (!ShellState.settingsOpen) { recorder.stop(); page.recording = ""; } }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            Field { Layout.fillWidth: true; placeholder: "⌕ filter by action, key or group…"; onEdited: t => page.filter = t }
            Button { text: "+ Add bind"; onClicked: page.draft = { label: "", kind: "exec", value: "" } }
        }

        // New-bind form
        Pill {
            visible: page.draft !== null
            Layout.fillWidth: true; Layout.preferredHeight: 84; color: Theme.bgRaised
            RowLayout {
                anchors.fill: parent; anchors.margins: 12; spacing: 10
                Field { Layout.preferredWidth: 180; label: "Label"; onEdited: t => page.draft = Object.assign({}, page.draft, { label: t }) }
                Choice { label: "Does"; value: page.draft?.kind ?? "exec"; options: [["exec", "Run command"], ["shell", "Shell action"], ["dispatch", "Hyprland dispatcher"]]
                         onPicked: v => page.draft = Object.assign({}, page.draft, { kind: v }) }
                Field { Layout.fillWidth: true; label: page.draft?.kind === "shell" ? "Shell action, e.g. launcher.toggle" : page.draft?.kind === "dispatch" ? "Dispatcher, e.g. workspace 3" : "Command"
                        onEdited: t => page.draft = Object.assign({}, page.draft, { value: t }) }
                Button { Layout.alignment: Qt.AlignBottom; text: page.recording === "new" ? "Press keys…" : "Record keys"; primary: true
                         enabled: (page.draft?.label ?? "") !== "" && (page.draft?.value ?? "") !== ""
                         onClicked: page.startRecording("new") }
                Button { Layout.alignment: Qt.AlignBottom; text: "Cancel"; onClicked: { recorder.stop(); page.draft = null; page.recording = ""; } }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 2
            model: page.rows
            section.property: "group"
            section.delegate: Glyph { required property string section; text: section.toUpperCase(); color: Theme.muted; font.pixelSize: 10; font.letterSpacing: 1; topPadding: 10; bottomPadding: 4 }
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property var clashes: page.clashWith(modelData)
                readonly property bool rec: page.recording === modelData.id
                width: list.width; height: 34; radius: 6
                color: rec ? Theme.accentSoft : (hover.containsMouse ? Theme.bgRaised : "transparent")
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 8
                    Glyph { text: row.modelData.label; Layout.fillWidth: true; elide: Text.ElideRight }
                    Glyph { visible: page.edited(row.modelData.id); text: "edited"; color: Theme.accent; font.pixelSize: 10 }
                    Glyph { visible: row.clashes.length > 0; text: "⚠ clashes with " + row.clashes.join(", "); color: Theme.error; font.pixelSize: 10 }
                    Glyph { visible: row.rec; text: "press keys… Esc cancels"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
                    Row {
                        visible: !row.rec; spacing: 3
                        Repeater {
                            model: (row.modelData.mods ? row.modelData.mods.split(" ").filter(m => m) : []).concat([row.modelData.key])
                            delegate: Rectangle {
                                required property string modelData
                                height: 20; width: k.implicitWidth + 10; radius: 4; color: Theme.surface
                                Glyph { id: k; anchors.centerIn: parent; text: parent.modelData; font.pixelSize: 10 }
                            }
                        }
                    }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent; hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: m => {
                        if (m.button === Qt.RightButton) {
                            // custom binds are removed; defaults go back to default
                            if (row.modelData.id.startsWith("custom.") || page.edited(row.modelData.id)) Settings.reset([page.path(row.modelData.id)], true);
                        } else page.startRecording(row.modelData.id);
                    }
                }
            }
        }
        Glyph { text: "Click a bind to record new keys · right-click resets (or removes a custom bind)"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
    }
}
