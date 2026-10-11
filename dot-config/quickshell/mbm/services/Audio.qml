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

    function clamp(v) { return Math.max(0, Math.min(1, v)); }
    function setVolume(v) { if (sink?.audio) { sink.audio.muted = false; sink.audio.volume = clamp(v); } }
    function setMicVolume(v) { if (source?.audio) source.audio.volume = clamp(v); }
    function toggleMute() { if (sink?.audio) sink.audio.muted = !sink.audio.muted; }
    function toggleMicMute() { if (source?.audio) source.audio.muted = !source.audio.muted; }
    function setDefaultSink(n) { Pipewire.preferredDefaultAudioSink = n; }
    function setDefaultSource(n) { Pipewire.preferredDefaultAudioSource = n; }
}
