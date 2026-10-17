import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "../theme"
import "../services"

PanelWindow {
    id: wall
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "fledge-wallpaper"
    color: Theme.bg

    // Physical pixels, so HiDPI and portrait screens get an asset (and a decode)
    // big enough to cover them. Logical size alone picked the 2560 landscape asset
    // for a 1440x2560 portrait screen and decoded it 1440 wide, then upscaled ~3x.
    readonly property real dpr: screen?.devicePixelRatio ?? 1
    readonly property real pw: (screen?.width ?? 1920) * dpr
    readonly property real ph: (screen?.height ?? 1080) * dpr

    // Moonrise is rendered at three sizes. Take the smallest that covers the screen
    // under PreserveAspectCrop, else the one that needs the least upscaling (the
    // ultrawide one only for ultrawide screens). Crop keeps the owl centred.
    readonly property var asset: {
        const sizes = pw / ph > 2.0 ? [[3440, 1440]] : [[1920, 1080], [2560, 1440]];
        for (const s of sizes) {
            if (Math.max(pw / s[0], ph / s[1]) <= 1) return s;
        }
        return sizes[sizes.length - 1];
    }
    readonly property string file: "moonrise-" + asset[0] + "x" + asset[1] + ".png"
    // How much the asset must grow to cover the screen.
    readonly property real cover: Math.max(pw / asset[0], ph / asset[1])

    // The chosen picture for this screen (monitor override, then the shared one); "" is Moonrise.
    // A file that is missing or won't decode falls back to Moonrise, with one warning per path.
    readonly property string chosen: Settings.wallpaperFor(screen?.name ?? "", Hyprland.monitorFor(screen)?.description ?? "")
    property bool failed: false
    onChosenChanged: failed = false
    readonly property bool custom: chosen !== "" && !failed

    readonly property string target: custom ? fileUrl(chosen) : "file://" + Theme.assets + "/" + file
    // Moonrise: both dimensions, so PreserveAspectCrop's decode fills (covers) the screen's physical
    // size instead of fitting its width. But Qt upscales on decode too, so when the asset is smaller
    // than that, decode it at its native size and let the GPU scale it: same picture, without a decoded
    // copy several times the asset's size. A user's picture is decoded no bigger than the physical screen.
    readonly property size decodeSize: custom || cover < 1 ? Qt.size(pw, ph) : Qt.size(asset[0], asset[1])

    // Two layers: the new picture loads in the hidden one and replaces the shown one only once it is
    // Ready, so a switch or a fallback never shows the bare background in between.
    property Image front: imgA
    function load() {
        const b = front === imgA ? imgB : imgA;
        b.want = target;
        b.sourceSize = decodeSize;
        b.source = target;
    }
    function settle(img) {
        if (img === front || img.want !== target) return;
        if (img.status === Image.Ready) {
            img.visible = true;
            front.visible = false;
            const old = front;
            front = img;
            old.source = "";   // free the old decode
        } else if (img.status === Image.Error && custom) {
            console.warn("fledge wallpaper: can't load " + chosen + ", using Moonrise");
            failed = true;
        }
    }
    onTargetChanged: load()
    Component.onCompleted: load()

    Image { id: imgA; property string want; anchors.fill: parent; visible: false; fillMode: Image.PreserveAspectCrop; asynchronous: true
            onStatusChanged: wall.settle(imgA) }
    Image { id: imgB; property string want; anchors.fill: parent; visible: false; fillMode: Image.PreserveAspectCrop; asynchronous: true
            onStatusChanged: wall.settle(imgB) }

    function fileUrl(p) { return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F"); }
}
