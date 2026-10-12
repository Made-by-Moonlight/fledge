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
    WlrLayershell.namespace: "mbm-wallpaper"
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

    Image {
        anchors.fill: parent
        visible: !wall.custom
        source: wall.custom ? "" : "file://" + Theme.assets + "/" + wall.file
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Both dimensions: with PreserveAspectCrop the decode fills (covers) the screen's
        // physical size instead of fitting its width. But Qt upscales on decode too, so
        // when the asset is smaller than that, decode it at its native size and let the
        // GPU scale it: same picture, without a decoded copy several times the asset's size.
        sourceSize: wall.cover >= 1 ? Qt.size(wall.asset[0], wall.asset[1]) : Qt.size(wall.pw, wall.ph)
    }

    // The user's picture, cropped to fill. Decoded no bigger than the screen's physical pixels.
    Image {
        id: pic
        anchors.fill: parent
        visible: wall.custom && status === Image.Ready
        source: wall.custom ? wall.fileUrl(wall.chosen) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(wall.pw, wall.ph)
        onStatusChanged: if (status === Image.Error && !wall.failed) {
            console.warn("mbm wallpaper: can't load " + wall.chosen + ", using Moonrise");
            wall.failed = true;
        }
    }
    function fileUrl(p) { return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F"); }
}
