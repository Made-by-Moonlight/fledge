pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Lock before suspend: hold a logind *delay* inhibitor so sleep waits (up to
// InhibitDelayMaxSec, 5 s by default) until the lock surface is up, then release it.
// The inhibitor is re-taken on resume. release() always runs within failsafe's
// interval, so a lock that never comes up can't make every suspend wait the full cap.
Singleton {
    id: root
    property bool pending: false
    property bool released: false
    signal preparingForSleep()
    signal resumed()

    // The held command is `cat` on a stdin pipe from the shell, not `sleep infinity`: when the
    // shell dies (crash, kill) the pipe closes, cat exits and the inhibitor goes with it.
    // Quickshell doesn't kill its children on exit, so an orphaned inhibitor would otherwise
    // make every later suspend wait out the full delay.
    Process {
        id: inhibitor
        running: Settings.lockOnSleep && !root.released
        stdinEnabled: true
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=mbm shell",
                  "--why=Lock the screen before sleep", "cat"]
    }
    function release() {
        failsafe.stop();
        pending = false;
        released = true;
    }

    Process {
        id: monitor
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: line => {
                if (!line.includes("PrepareForSleep")) return;
                if (line.includes("(true,)")) {
                    root.pending = true;
                    failsafe.restart();
                    root.preparingForSleep();
                } else if (line.includes("(false,)")) {
                    root.release();     // in case sleep went ahead without us (delay cap hit)
                    root.released = false;
                    root.resumed();
                }
            }
        }
        onExited: again.start()
    }
    Timer { id: again; interval: 2000; onTriggered: monitor.running = true }
    // Under logind's 5 s cap: if the lock isn't secure by now it won't be before sleep anyway.
    Timer { id: failsafe; interval: 4000; onTriggered: if (root.pending) root.release() }
}
