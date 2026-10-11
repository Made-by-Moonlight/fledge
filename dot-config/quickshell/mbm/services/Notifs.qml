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

    readonly property int historyCap: 100
    // Pop-up expiry lives here, not in the cards: re-creating cards must not reset it.
    property var deadlines: new Map()

    // Senders are untrusted and StyledText renders <a> and <img>. Whitelist, one pass:
    // a "<" survives only as part of an exact <b> <i> <u> or closing tag (no attributes);
    // every other "<" becomes &lt;, so no input can build any other tag. Entities pass through.
    function sanitize(text) {
        return (text ?? "").replace(/<\/?[biu]>|</gi, m => m.length > 1 ? m.toLowerCase() : "&lt;");
    }

    // freedesktop: -1 server default, 0 never, >0 that long. Quickshell reports ms (measured: -t 2000 expired at ~2 s).
    // Critical ones never expire. Returns ms, or 0 for never.
    function timeoutMs(n) {
        if (n.urgency === NotificationUrgency.Critical) return 0;
        const t = n.expireTimeout;
        if (t < 0) return Settings.notifTimeout;
        return Math.round(t);
    }

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
            root.trimHistory(n);
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) return;
            root.popups = [n, ...root.popups].slice(0, root.maxPopups);
            const ms = root.timeoutMs(n);
            if (ms > 0) root.deadlines.set(n, Date.now() + ms);
            else root.deadlines.delete(n);
            if (root.deadlines.size > 0) expiry.start();
        }
    }

    Timer {
        id: expiry
        interval: 250
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (const [n, at] of [...root.deadlines]) if (at <= now) root.unpop(n);
            if (root.deadlines.size === 0) stop();
        }
    }

    // Oldest non-popup entries go first once history passes the cap.
    function trimHistory(fresh) {
        const all = server.trackedNotifications.values;
        let extra = all.length + (all.includes(fresh) ? 0 : 1) - historyCap;
        for (const n of [...all]) {
            if (extra <= 0) break;
            if (n === fresh || popups.includes(n)) continue;
            n.dismiss();
            extra--;
        }
    }

    function unpop(n) { deadlines.delete(n); popups = popups.filter(p => p && p !== n); }
    function remember(n) { lastDismissed = { app: n.appName, summary: n.summary, body: n.body }; }
    function dismiss(n) {
        if (!n) return;
        unpop(n);
        remember(n);
        if (n.tracked) n.dismiss();  // invoking an action may already have closed it
    }
    function newest() { return popups[0] ?? history[history.length - 1] ?? null; }
    function dismissLast() { dismiss(newest()); }
    function dismissAll() {
        const all = [...history];
        if (all.length > 0) remember(all[all.length - 1]);
        for (const n of all) n.dismiss();
        popups = [];
        deadlines.clear();
    }
    function dismissSummary(text) { dismiss(history.find(n => n.summary.includes(text)) ?? null); }
    // Same choice as clicking a card: the default action, then dismiss.
    function invokeDefault(n) {
        if (!n) return;
        // Read everything first: closing after the action may destroy the object.
        const a = n.actions.find(a => a.identifier === "default");
        unpop(n);
        remember(n);
        if (a) a.invoke();
        try { if (n.tracked) n.dismiss(); } catch (e) {}
    }
    function invokeLast() { invokeDefault(newest()); }
    // Re-sends the last dismissed one (the server can't un-dismiss).
    function restoreLast() {
        if (lastDismissed) Quickshell.execDetached(["notify-send", "-a", lastDismissed.app, lastDismissed.summary, lastDismissed.body]);
    }
    function toggleDnd() { dnd = !dnd; if (dnd) popups = []; }
}
