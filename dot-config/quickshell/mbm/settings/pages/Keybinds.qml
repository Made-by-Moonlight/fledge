import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"
import ".."
import "../DspShort.js" as DspShort

Item {
    id: page
    property string filter: ""
    property string recording: ""          // id being re-recorded, or "new"
    property var draft: null               // bind being added or edited: {id?, label, kind, value}; id set = editing
    property var dspNames: []              // every hl.dsp name, the list `mbm settings check` uses

    FileView {
        path: Settings.home + "/.local/share/mbm/lib/dsp-names.json"
        onLoaded: { try { page.dspNames = JSON.parse(text()).names ?? []; } catch (e) { console.warn("mbm settings: unreadable " + path); } }
        // Without the list only parse errors show; say why rather than quietly checking less.
        onLoadFailed: error => console.warn("mbm settings: could not read " + path + " (" + FileViewError.toString(error) + "); dispatcher names go unchecked until mbm settings check")
    }

    // What the form edits: "exec", "shell", "dsp", or "" for an action it can't show (a list mixing kinds).
    function kindOf(a) {
        if (a?.exec !== undefined) return "exec";
        if (a?.shell !== undefined) return "shell";
        return DspShort.format(a) !== "" ? "dsp" : "";
    }
    function textOf(a) { const k = kindOf(a); return k === "dsp" ? DspShort.format(a) : k ? a[k] : ""; }
    function draftAction(d) { return d.kind === "dsp" ? DspShort.parse(d.value) : { [d.kind]: d.value }; }
    // Why the draft's dispatcher can't be saved ("" = it can). Names are checked once the list has
    // loaded; `mbm settings check` checks them again either way.
    readonly property string draftError: {
        const d = page.draft;
        if (!d || d.kind !== "dsp" || d.value === "") return "";
        return page.dspNames.length ? DspShort.check(d.value, page.dspNames) : (DspShort.parse(d.value).error ?? "");
    }
    function openDraft(d) {
        draft = d;
        labelField.text = d.label;
        valueField.text = d.value;
    }
    function saveDraft() {
        const d = draft, b = effective[d.id], pairs = [];
        draft = null;
        if (!b) return;                    // removed meanwhile (a reset, another window)
        const label = d.label.replace(/,/g, ""), action = draftAction(d);
        if (label !== b.label) pairs.push([path(d.id) + ".label", label]);
        if (JSON.stringify(action) !== JSON.stringify(b.action)) pairs.push([path(d.id) + ".action", action]);
        if (pairs.length) Settings.set(pairs, true);
    }

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
        .filter(b => !filter || (b.label + " " + combo(b) + " " + b.group + " " + DspShort.format(b.action)).toLowerCase().includes(filter.toLowerCase()))
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

    onRecordingChanged: ShellState.recording = recording !== ""
    Component.onDestruction: ShellState.recording = false

    function startRecording(id) { recording = id; recorder.start(); }

    KeyRecorder {
        id: recorder
        onRecorded: (mods, key) => {
            if (page.recording === "new") {
                const d = page.draft;
                // The names list may have loaded (or the draft changed) since Record was enabled.
                if (!d || page.draftError !== "") {
                    page.recording = "";
                    Settings.lastError = d ? page.draftError : "Nothing to save: the new bind's form was closed.";
                    return;
                }
                Settings.set([[page.path(page.nextCustomId()), { mods, key, label: d.label.replace(/,/g, ""), group: "Custom", action: page.draftAction(d) }]], true);
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
            Button { text: "+ Add bind"; onClicked: { recorder.stop(); page.recording = ""; page.openDraft({ label: "", kind: "exec", value: "" }); } }
        }

        // Form for a new bind, or for what an existing one does
        Pill {
            id: draftForm
            visible: page.draft !== null
            Layout.fillWidth: true; Layout.preferredHeight: formRows.implicitHeight + 24; color: Theme.bgRaised
            readonly property bool ready: (page.draft?.label ?? "") !== "" && (page.draft?.value ?? "") !== "" && page.draftError === ""
            // Two rows: on one row the action field was squeezed to nothing beside the buttons.
            ColumnLayout {
                id: formRows
                anchors.fill: parent; anchors.margins: 12; spacing: 8
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Field { id: labelField; Layout.preferredWidth: 240; label: "Label"; onEdited: t => page.draft = Object.assign({}, page.draft, { label: t }) }
                    Choice { label: "Does"; value: page.draft?.kind ?? "exec"; options: [["exec", "Run command"], ["shell", "Shell action"], ["dsp", "Hyprland dispatcher"]]
                             onPicked: v => page.draft = Object.assign({}, page.draft, { kind: v }) }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Field { id: valueField; Layout.fillWidth: true
                            label: page.draft?.kind === "shell" ? "Shell action, e.g. launcher.toggle" : page.draft?.kind === "dsp" ? "Dispatcher, e.g. window.move workspace=3 follow=false" : "Command"
                            onEdited: t => page.draft = Object.assign({}, page.draft, { value: t }) }
                    // Adding: the keys are recorded last. Editing: the keys stay (click the row to re-record them).
                    Button { Layout.alignment: Qt.AlignBottom; visible: !page.draft?.id; text: page.recording === "new" ? "Press keys…" : "Record keys"; primary: true
                             enabled: draftForm.ready
                             onClicked: page.startRecording("new") }
                    Button { Layout.alignment: Qt.AlignBottom; visible: !!page.draft?.id; text: "Save"; primary: true
                             enabled: draftForm.ready
                             onClicked: page.saveDraft() }
                    Button { Layout.alignment: Qt.AlignBottom; text: "Cancel"; onClicked: { recorder.stop(); page.draft = null; page.recording = ""; } }
                }
                Glyph { visible: page.draftError !== ""; text: "⚠ " + page.draftError; color: Theme.error; font.pixelSize: Theme.fontSmall }
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
                    Glyph { text: row.modelData.label; Layout.preferredWidth: implicitWidth; Layout.maximumWidth: row.width * 0.4; elide: Text.ElideRight }
                    // Dispatcher binds show what they do, in the editor's short form.
                    Glyph { text: DspShort.format(row.modelData.action); Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.muted; font.pixelSize: Theme.fontSmall }
                    Glyph {
                        text: "✎ edit"; color: editArea.containsMouse ? Theme.accent : Theme.muted; font.pixelSize: Theme.fontSmall
                        visible: !row.rec && (hover.containsMouse || editArea.containsMouse) && page.kindOf(row.modelData.action) !== ""
                        MouseArea {
                            id: editArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
                            onClicked: { recorder.stop(); page.recording = ""; page.openDraft({ id: row.modelData.id, label: row.modelData.label, kind: page.kindOf(row.modelData.action), value: page.textOf(row.modelData.action) }); }
                        }
                    }
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
                    z: -1   // under the row, so its edit button gets the click
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
        Glyph { text: "Click a bind to record new keys · ✎ edits what it does · right-click resets (or removes a custom bind)"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
    }
}
