pragma Singleton
import Quickshell
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

    // Volume/mute of a node are only live while something tracks it.
    PwObjectTracker { objects: [root.sink, root.source, ...root.sinks, ...root.sources] }

    // PipeWire values only update after the daemon round-trips, so back-to-back steps and toggles
    // build on what was last asked for, not on the (possibly stale) live value. Cleared shortly after
    // the last request, once the live value has had time to catch up.
    property real pendingVolume: -1
    property int pendingMuted: -1    // -1 none, 0 unmuted, 1 muted
    property int pendingMicMuted: -1
    Timer { id: settle; interval: 600; onTriggered: { root.pendingVolume = -1; root.pendingMuted = -1; root.pendingMicMuted = -1; } }

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
    function setDefaultSink(n) { Pipewire.preferredDefaultAudioSink = n; }
    function setDefaultSource(n) { Pipewire.preferredDefaultAudioSource = n; }
}
