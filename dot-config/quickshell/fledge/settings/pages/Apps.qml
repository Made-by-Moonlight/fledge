import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"
import ".."
import "../Layout.js" as Geom

// Per-app window rules (apps.<class>) and the default opacity (windows.opacity), generated into
// apps.lua by apply. Hyprland re-applies opacity to open windows on reload, so a change shows at
// once; placement only affects windows opened afterwards. A field is cleared by writing null
// (the merge drops it), which works the same for a shipped entry and one of the user's.
Flickable {
    id: page
    contentHeight: col.implicitHeight; clip: true

    property string expanded: ""
    // settings.app(class): open that row.
    function takeRequest() { if (ShellState.appsExpand !== "") { expanded = ShellState.appsExpand; ShellState.appsExpand = ""; } }
    Component.onCompleted: takeRequest()
    Connections { target: ShellState; function onAppsExpandChanged() { page.takeRequest(); } }

    // Open windows by class (Wayland app id; XWayland windows report their class there too).
    // Quickshell's own windows are left out: they're the shell.
    readonly property var open: {
        const n = {};
        for (const t of ToplevelManager.toplevels.values) {
            const c = t.appId;
            if (!c || c === "org.quickshell") continue;
            n[c] = (n[c] ?? 0) + 1;
        }
        return n;
    }
    readonly property var openClasses: Object.keys(open).sort((a, b) => name(a).localeCompare(name(b)))
    // Plus the row asked for by settings.app(class), so it shows before it has an entry.
    readonly property var configured: [...new Set([...Object.keys(Settings.apps), ...(expanded ? [expanded] : [])])]
        .filter(c => !(c in open)).sort((a, b) => name(a).localeCompare(name(b)))
    // Monitors as Displays keys them, labelled the same way.
    readonly property var monitors: Hyprland.monitors.values.map(m => ({ key: Geom.keyFor(m, Hyprland.monitors.values), label: m.description || m.name }))

    function desktop(c) { return DesktopEntries.heuristicLookup(c); }
    function name(c) { return desktop(c)?.name || c; }
    function icon(c) { const i = desktop(c)?.icon ?? ""; return i ? Quickshell.iconPath(i, true) : ""; }
    // Settings paths are jq paths: a class with a quote or backslash can't be one (settings.sh valid_path).
    function editable(c) { return !/["\\]/.test(c); }
    function path(c, field) { return '.apps["' + c + '"]' + (field ? "." + field : ""); }
    function pct(v) { return Math.round(v * 100) + "%"; }
    function summary(c) {
        const a = Settings.apps[c] ?? {};
        const parts = [a.opacity ? pct(a.opacity.active) + " / " + pct(a.opacity.inactive) : "default"];
        if (a.workspace) parts.push("workspace " + a.workspace);
        if (a.monitor) parts.push(monitorLabel(a.monitor));
        return parts.join(" · ");
    }
    function monitorLabel(key) {
        const m = monitors.find(m => m.key === key);
        return m ? m.label : Geom.label(key) + " (not connected)";
    }
    function write(pairs) { Settings.set(pairs, true); }
    function forget(c) { write([[path(c), null]]); if (expanded === c) expanded = ""; }
    // The user changed a shipped entry: offer to go back to it.
    function changedDefault(c) { return Settings.defaults.apps?.[c] !== undefined && Settings.user.apps?.[c] !== undefined; }

    ColumnLayout {
        id: col
        width: page.width; spacing: 14

        Glyph { text: "Opacity and placement per app. Opacity shows on open windows straight away; placement applies to windows opened from now on."
                color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }

        // The default, for every window without its own.
        Pill {
            Layout.fillWidth: true; implicitHeight: def.implicitHeight + 24; color: Theme.bgRaised
            OpacityEditor {
                id: def
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                title: "Default for every window"
                value: Settings.windowOpacity
                onSave: v => page.write([[".windows.opacity", v]])
            }
        }

        Repeater {
            model: [["Open now", page.openClasses], ["Configured, not open", page.configured]]
            delegate: ColumnLayout {
                id: group
                required property var modelData
                Layout.fillWidth: true; spacing: 4
                visible: modelData[1].length > 0
                Glyph { text: group.modelData[0]; color: Theme.muted; font.pixelSize: Theme.fontSmall }
                Repeater {
                    model: group.modelData[1]
                    delegate: Rectangle {
                        id: row
                        required property string modelData
                        readonly property string cls: modelData
                        Layout.fillWidth: true
                        readonly property var app: Settings.apps[cls] ?? ({})
                        readonly property bool isOpen: cls === page.expanded
                        readonly property string placement: app.workspace ? "workspace" : app.monitor ? "monitor" : "anywhere"
                        implicitHeight: body.implicitHeight + 16
                        radius: Theme.radius
                        color: isOpen ? Theme.bgRaised : (hover.containsMouse ? Theme.surface : "transparent")

                        MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

                        ColumnLayout {
                            id: body
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 10

                            Item {
                                Layout.fillWidth: true; implicitHeight: head.implicitHeight
                                RowLayout {
                                    id: head
                                    anchors.fill: parent; spacing: 10
                                    Item {
                                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                                        IconImage { anchors.fill: parent; source: page.icon(row.cls); visible: source != "" }
                                        Glyph { anchors.centerIn: parent; text: "󰣆"; color: Theme.muted; visible: page.icon(row.cls) === "" }
                                    }
                                    Column {
                                        Layout.fillWidth: true
                                        Glyph { text: page.name(row.cls); width: parent.width; elide: Text.ElideRight }
                                        Glyph {
                                            width: parent.width; elide: Text.ElideRight; color: Theme.muted; font.pixelSize: Theme.fontSmall; textFormat: Text.PlainText
                                            // The class is what's matched: shown unless the name already is it.
                                            readonly property int n: page.open[row.cls] ?? 0
                                            text: [page.name(row.cls) !== row.cls ? row.cls : "", n ? n + (n === 1 ? " window" : " windows") : ""].filter(s => s).join(" · ")
                                            visible: text !== ""
                                        }
                                    }
                                    Glyph { text: page.summary(row.cls); color: Settings.apps[row.cls] ? Theme.accent : Theme.muted; font.pixelSize: Theme.fontSmall }
                                    Glyph { text: row.isOpen ? "⌄" : "›"; color: Theme.muted }
                                }
                                // The header toggles the editor; the editor below takes its own clicks.
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: page.expanded = row.isOpen ? "" : row.cls }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; Layout.leftMargin: 32; spacing: 12
                                visible: row.isOpen

                                Glyph { visible: !page.editable(row.cls); color: Theme.error; wrapMode: Text.Wrap; Layout.fillWidth: true
                                        text: "This class has a quote or backslash, which settings can't store. Edit ~/.config/fledge/settings.json by hand." }

                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 12
                                    enabled: page.editable(row.cls); opacity: enabled ? 1 : 0.5
                                    Choice {
                                        label: "Opacity"
                                        options: [["default", "Default"], ["own", "Own"]]
                                        value: row.app.opacity ? "own" : "default"
                                        onPicked: v => page.write([[page.path(row.cls, "opacity"), v === "own" ? Settings.windowOpacity : null]])
                                    }
                                    OpacityEditor {
                                        Layout.fillWidth: true
                                        visible: !!row.app.opacity
                                        value: row.app.opacity ?? Settings.windowOpacity
                                        onSave: v => page.write([[page.path(row.cls, "opacity"), v]])
                                    }
                                    Choice {
                                        label: "Opens on"
                                        options: [["anywhere", "Anywhere"], ["workspace", "Workspace"], ["monitor", "Monitor"]]
                                        value: row.placement
                                        onPicked: v => {
                                            if (v === row.placement) return;
                                            const ws = v === "workspace" ? 1 : null;
                                            const mon = v === "monitor" ? (page.monitors[0]?.key ?? null) : null;
                                            page.write([[page.path(row.cls, "workspace"), ws], [page.path(row.cls, "monitor"), mon]]);
                                        }
                                    }
                                    Stepper {
                                        visible: row.placement === "workspace"
                                        label: "Workspace"; from: 1; to: 10; value: row.app.workspace ?? 1
                                        onChanged: v => page.write([[page.path(row.cls, "workspace"), Math.round(v)]])
                                    }
                                    Choice {
                                        visible: row.placement === "monitor"
                                        label: "Monitor"
                                        // A saved monitor that isn't connected stays listed, so it can stay picked.
                                        options: {
                                            const o = page.monitors.map(m => [m.key, m.label]);
                                            if (row.app.monitor && !o.some(x => x[0] === row.app.monitor)) o.push([row.app.monitor, page.monitorLabel(row.app.monitor)]);
                                            return o;
                                        }
                                        value: row.app.monitor ?? ""
                                        onPicked: v => page.write([[page.path(row.cls, "monitor"), v]])
                                    }
                                    RowLayout {
                                        spacing: Theme.gap
                                        Button { text: "Restore the shipped setting"; visible: page.changedDefault(row.cls)
                                                 onClicked: Settings.reset([page.path(row.cls)], true) }
                                        Button { text: "Forget " + page.name(row.cls); visible: Settings.apps[row.cls] !== undefined
                                                 onClicked: page.forget(row.cls) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: Theme.gap
            Field {
                id: addField; Layout.fillWidth: true
                label: "Add an app by window class"; placeholder: "e.g. org.gnome.Nautilus"
                onCommitted: t => add.clicked()
            }
            Button {
                id: add; Layout.alignment: Qt.AlignBottom; text: "Add"
                readonly property string cls: addField.text.trim()
                enabled: cls !== "" && page.editable(cls) && Settings.apps[cls] === undefined
                onClicked: { if (!enabled) return; page.expanded = cls; page.write([[page.path(cls), {}]]); addField.text = ""; }
            }
        }
    }
}
