pragma Singleton
import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// One notification server for the session. Every notification is tracked
// (history); pop-ups are the newest few. DND keeps them out of pop-ups only.
Singleton {
    id: root
    property bool dnd: false
    property var popups: []
    property var lastDismissed: null
    readonly property var history: server.trackedNotifications.values
    readonly property int maxPopups: 5

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: n => {
            n.tracked = true;
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) return;
            root.popups = [n, ...root.popups].slice(0, root.maxPopups);
        }
    }

    function unpop(n) { popups = popups.filter(p => p && p !== n); }
    function dismiss(n) {
        if (!n) return;
        unpop(n);
        lastDismissed = { app: n.appName, summary: n.summary, body: n.body };
        n.dismiss();
    }
    function newest() { return popups[0] ?? history[history.length - 1] ?? null; }
    function dismissLast() { dismiss(newest()); }
    function dismissAll() { for (const n of [...history]) n.dismiss(); popups = []; }
    function dismissSummary(text) { dismiss(history.find(n => n.summary.includes(text)) ?? null); }
    function invokeLast() {
        const n = newest();
        const a = n?.actions.find(a => a.identifier === "default") ?? n?.actions[0];
        if (a) a.invoke();
    }
    // Re-sends the last dismissed one (the server can't un-dismiss).
    function restoreLast() {
        if (lastDismissed) Quickshell.execDetached(["notify-send", "-a", lastDismissed.app, lastDismissed.summary, lastDismissed.body]);
    }
    function toggleDnd() { dnd = !dnd; if (dnd) popups = []; }
}
