pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: z
    property var zones: []
    property string preview: ""      // local time in the chosen zone
    Process {
        running: true
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector { onStreamFinished: z.zones = text.split("\n").filter(s => s !== "") }
    }
    Process {
        id: clock
        command: ["env", "TZ=" + Installer.timezone, "date", "+%H:%M · %a %d %b"]
        stdout: StdioCollector { onStreamFinished: z.preview = text.trim() }
    }
    Connections { target: Installer; function onTimezoneChanged() { clock.running = true; } }
    Timer { interval: 30000; repeat: true; running: true; triggeredOnStart: true; onTriggered: clock.running = true }
}
