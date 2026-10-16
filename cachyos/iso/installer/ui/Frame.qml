import QtQuick
import "../theme"
import "../services"
// Unused as types: the Loader below picks a page by URL. Quickshell only scans the
// directories reachable through imports, and pages import ones nothing else does.
import "../steps"

// Rail + the current step + footer. Return goes forward and Esc back when the
// focused field doesn't take the key itself (Input stops Return).
FocusScope {
    id: frame
    focus: true
    // When the current page appeared; Review's Return waits a moment after it.
    property real pageAt: 0
    // A held Return repeats, and a repeat must not walk on through the pages:
    // one press, one step. Review's Return erases a disk, so it also has to be
    // a press made after Review was up, not a quick second tap meant for the
    // page before.
    function forward(ev) {
        if (ev.isAutoRepeat) return;
        if (Installer.current === "review" && Date.now() - pageAt < 500) return;
        Installer.next();
    }
    Keys.onReturnPressed: ev => forward(ev)
    Keys.onEnterPressed: ev => forward(ev)
    Keys.onEscapePressed: ev => { if (!ev.isAutoRepeat) Installer.back(); }
    Rail { id: rail; width: 300; anchors { top: parent.top; bottom: parent.bottom; left: parent.left } }
    Item {
        anchors { left: rail.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 56 }
        Loader {
            id: page
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top; bottomMargin: 24 }
            focus: true
            source: "../steps/" + Installer.steps[Installer.step].page + ".qml"
            // The old page's focused field is gone: take focus back so Return/Esc
            // still reach this scope (a page's own focusInput() survives this).
            onLoaded: { frame.pageAt = Date.now(); forceActiveFocus(); }
        }
        Footer { id: footer; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } }
    }
}
