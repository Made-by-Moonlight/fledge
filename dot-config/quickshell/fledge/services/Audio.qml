pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick

Singleton {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool ready: sink?.audio != null
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? true
    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? true
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    // Apps playing audio: Quickshell counts a playback stream as a sink (it takes the app's audio
    // in). By app name then id, so rows keep their place.
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isSink && n.isStream)
        .sort((a, b) => appName(a).localeCompare(appName(b)) || a.id - b.id)

    // Volume/mute of a node are only live while something tracks it.
    PwObjectTracker { objects: [root.sink, root.source, ...root.sinks, ...root.sources, ...root.streams] }

    // Which app (Settings › Apps window class) a stream belongs to; see
    // docs/superpowers/specs/2026-10-23-app-volume-design.md. First by name: the stream's binary or
    // application name is a known class, ignoring case (so mpv run from a terminal is mpv, not the
    // terminal). Then by process: the stream's process or its nearest ancestor owns a window (Zen
    // plays from its window's process, Electron apps such as Vesktop from a child of it).
    readonly property var openClasses: [...new Set(ToplevelManager.toplevels.values.map(t => t.appId).filter(c => c && c !== "org.quickshell"))]
    readonly property var knownClasses: {
        const m = {};
        for (const c of [...Object.keys(Settings.apps), ...openClasses]) m[c.toLowerCase()] = c;
        return m;
    }
    // A stream's key for the caches below: PipeWire reuses node ids, never object serials, so a new
    // stream on an old id doesn't inherit the old one's answers.
    function keyOf(n) { return n.id + "/" + (n.properties["object.serial"] ?? ""); }
    // stream key → class from the process walk ("" = no window up the tree). A miss is dropped when
    // the windows change: the app's window may just not have been mapped yet.
    property var walked: ({})
    onOpenClassesChanged: {
        const w = {};
        for (const k in walked) if (walked[k] !== "") w[k] = walked[k];
        walked = w;
    }
    // The class, "" when the stream belongs to no app, undefined while the process walk is pending.
    function classOf(n) {
        const p = n?.properties ?? {};
        for (const v of [p["application.process.binary"], p["application.name"]]) {
            const c = v ? knownClasses[String(v).toLowerCase()] : undefined;
            if (c) return c;
        }
        return n ? walked[keyOf(n)] : undefined;
    }
    readonly property var unwalked: streams.filter(n => classOf(n) === undefined).map(keyOf)
    onUnwalkedChanged: walkSoon.restart()
    Timer {
        id: walkSoon; interval: 150
        onTriggered: if (!walker.running && root.unwalked.length) {
            walker.command = ["sh", "-c", root.walkScript, "sh", ...root.unwalked];
            walker.running = true;
        }
    }
    // Args: stream keys (<node id>/<serial>). Prints "<key> <class>" per stream. The process id is on the stream node
    // for apps that go through pipewire-pulse (browsers, Electron), and only on its client object for
    // native PipeWire ones (pw-cat, mpv's pipewire output), so pw-dump answers both.
    readonly property string walkScript: `
        wins=$(hyprctl clients -j | jq -r '.[] | "\\(.pid) \\(.class)"')
        pw-dump | jq -r --args '
            (map({key: (.id | tostring), value: .info.props}) | from_entries) as $p
            | $ARGS.positional[] as $k
            | ($p[$k | split("/")[0]] // {}) as $n
            | "\\($k) \\($n["application.process.id"] // $p[($n["client.id"] // "" | tostring)]["application.process.id"] // "")"' "$@" |
        while read -r id q; do
            c=""
            while [ "\${q:-0}" -gt 1 ] 2>/dev/null; do
                c=$(printf '%s\\n' "$wins" | awk -v q="$q" '$1 == q { print substr($0, length($1) + 2); exit }')
                [ -n "$c" ] && break
                q=$(awk '/^PPid:/ { print $2 }' "/proc/$q/status" 2>/dev/null)
            done
            printf '%s %s\\n' "$id" "$c"
        done`
    Process {
        id: walker
        stdout: StdioCollector {
            onStreamFinished: {
                const w = Object.assign({}, root.walked);
                for (const line of text.split("\n")) {
                    const m = line.match(/^([0-9]+\/[0-9]*) ?(.*)$/);
                    if (m) w[m[1]] = m[2];
                }
                root.walked = w;
            }
        }
        onRunningChanged: if (!running && root.unwalked.length) walkSoon.restart()
    }
    // An app's streams, and its volume/mute as one: the loudest stream's volume; muted when all are.
    function streamsOf(cls) { return streams.filter(n => classOf(n) === cls); }
    function appVolume(cls) { return Math.max(0, ...streamsOf(cls).map(n => n.audio?.volume ?? 0)); }
    function appMuted(cls) { const s = streamsOf(cls); return s.length > 0 && s.every(n => n.audio?.muted); }
    function setAppVolume(cls, v) { for (const n of streamsOf(cls)) setStreamVolume(n, v); }
    function toggleAppMute(cls) { const m = !appMuted(cls); for (const n of streamsOf(cls)) if (n.audio) n.audio.muted = m; }

    // Settings › Apps "Starts at": a stream of an app with apps.<class>.volume is set to it once,
    // when it first maps to the app and its volume is live (after WirePlumber has restored its own
    // last-used value). Retried while any stream is waiting on either.
    property var started: ({})   // stream key → true once handled
    Timer { interval: 250; repeat: true; running: root.streams.some(n => !root.started[root.keyOf(n)]); onTriggered: root.startVolumes() }
    function startVolumes() {
        const s = Object.assign({}, started);
        let changed = false;
        for (const n of streams) {
            const k = keyOf(n);
            if (s[k] || !n.ready || !n.audio) continue;
            const c = classOf(n);
            if (c === undefined) continue;   // the process walk will come back to it
            const v = c ? Settings.apps[c]?.volume : undefined;
            if (typeof v === "number") setStreamVolume(n, v);
            s[k] = true;
            changed = true;
        }
        // Forget streams that are gone, so the maps don't grow for ever.
        const live = new Set(streams.map(keyOf));
        for (const k in s) if (!live.has(k)) { delete s[k]; changed = true; }
        if (Object.keys(walked).some(k => !live.has(k))) {
            const w = {};
            for (const k in walked) if (live.has(k)) w[k] = walked[k];
            walked = w;
        }
        if (changed) started = s;
    }
    onStreamsChanged: Qt.callLater(startVolumes)
    onWalkedChanged: Qt.callLater(startVolumes)

    // PipeWire values only update after the daemon round-trips, so back-to-back steps and toggles
    // build on what was last asked for, not on the (possibly stale) live value. Cleared shortly after
    // the last request, once the live value has had time to catch up.
    property real pendingVolume: -1
    property int pendingMuted: -1    // -1 none, 0 unmuted, 1 muted
    property int pendingMicMuted: -1
    property real pendingMicVolume: -1
    Timer { id: settle; interval: 600; onTriggered: { root.pendingVolume = -1; root.pendingMuted = -1; root.pendingMicMuted = -1; root.pendingMicVolume = -1; } }

    function clamp(v) { return isNaN(v) ? 0 : Math.max(0, Math.min(1, v)); }
    function setVolume(v) { if (sink?.audio) { sink.audio.muted = false; sink.audio.volume = clamp(v); } }
    function setMicVolume(v) { if (source?.audio) source.audio.volume = clamp(v); }
    // Step the volume by delta (fraction); returns the target volume, or -1 without a sink.
    function stepVolume(delta) {
        if (!sink?.audio || isNaN(delta)) return -1;
        const t = clamp((pendingVolume >= 0 ? pendingVolume : volume) + delta);
        pendingVolume = t;
        pendingMuted = 0;
        settle.restart();
        setVolume(t);
        return t;
    }
    function stepMicVolume(delta) {
        if (!source?.audio || isNaN(delta)) return -1;
        const t = clamp((pendingMicVolume >= 0 ? pendingMicVolume : micVolume) + delta);
        pendingMicVolume = t;
        settle.restart();
        setMicVolume(t);
        return t;
    }
    // Toggles return the state they set (true = muted); null when there is no node.
    function toggleMute() {
        if (!sink?.audio) return null;
        const m = pendingMuted >= 0 ? pendingMuted === 0 : !muted;
        pendingMuted = m ? 1 : 0;
        settle.restart();
        sink.audio.muted = m;
        return m;
    }
    function toggleMicMute() {
        if (!source?.audio) return null;
        const m = pendingMicMuted >= 0 ? pendingMicMuted === 0 : !micMuted;
        pendingMicMuted = m ? 1 : 0;
        settle.restart();
        source.audio.muted = m;
        return m;
    }
    // A stream's app name (the Settings › Apps name when it maps to an app), and its icon name
    // ("" when there is none).
    function appName(n) {
        const c = classOf(n);
        if (c) return DesktopEntries.heuristicLookup(c)?.name || c;
        return n?.properties["application.name"] || n?.description || n?.name || "";
    }
    function appIcon(n) {
        const p = n?.properties ?? {};
        const c = classOf(n);
        return p["application.icon-name"] || DesktopEntries.heuristicLookup(c || p["application.process.binary"] || appName(n))?.icon || "";
    }
    function setStreamVolume(n, v) { if (n?.audio) { n.audio.muted = false; n.audio.volume = clamp(v); } }
    function stepStreamVolume(n, delta) { if (n?.audio && !isNaN(delta)) setStreamVolume(n, n.audio.volume + delta); }
    function toggleStreamMute(n) { if (n?.audio) n.audio.muted = !n.audio.muted; }
    function setDefaultSink(n) { Pipewire.preferredDefaultAudioSink = n; }
    function setDefaultSource(n) { Pipewire.preferredDefaultAudioSource = n; }
}
