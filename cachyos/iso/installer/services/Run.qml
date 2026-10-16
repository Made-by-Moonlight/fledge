pragma Singleton
import Quickshell
import QtQuick

Singleton {
    property string state: "idle"
    function start(text) { state = "running"; }
    function retryDesktop() {}
    function reboot() {}
    function cleanup(after) { if (after) after(); }
}
