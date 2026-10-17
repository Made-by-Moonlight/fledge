import QtQuick
import QtQuick.Shapes
import "../theme"

// The dark frame as one even-odd path: the whole screen minus the desktop. The desktop's
// outline has rounded corners, and along the bar edge it steps down under each section's tab
// (concave fillet off the strip, straight side, convex corner into the tab's bottom edge).
// One path on one surface, so strip, tabs, borders and fillets have no joins that could seam.
// The path is drawn for a top bar; a bottom bar mirrors it.
Shape {
    id: frame
    property bool atTop: true
    // Tabs as [left, right] x spans of their bottom edges. A tab that starts at 0 or ends at the
    // width hangs from that corner: the side border runs straight into it.
    property var tabs: []

    // CurveRenderer anti-aliases curves without a multisampled fullscreen layer.
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { origin.y: frame.height / 2; yScale: frame.atTop ? 1 : -1 }

    readonly property string svg: {
        const W = width, H = height, f = Theme.frame, r = Theme.frameRadius;
        const S = Theme.frame, D = Theme.barHeight, c = Math.min(Theme.tabRadius, (D - S) / 2);
        // Tabs too close for two fillets between them become one tab.
        const spans = [];
        for (const t of [...tabs].sort((a, b) => a[0] - b[0])) {
            const last = spans[spans.length - 1];
            if (last && t[0] - last[1] < 2 * c + 2) last[1] = Math.max(last[1], t[1]);
            else spans.push([t[0], t[1]]);
        }
        const startD = spans.length && spans[0][0] <= f ? D : S;
        const endD = spans.length && spans[spans.length - 1][1] >= W - f ? D : S;

        let p = `M0 0H${W}V${H}H0Z M${f + r} ${startD}`;
        for (const [L, R] of spans) {
            if (L > f) p += `H${L - c}A${c} ${c} 0 0 1 ${L} ${S + c}V${D - c}A${c} ${c} 0 0 0 ${L + c} ${D}`;
            if (R < W - f) p += `H${R - c}A${c} ${c} 0 0 0 ${R} ${D - c}V${S + c}A${c} ${c} 0 0 1 ${R + c} ${S}`;
        }
        p += `H${W - f - r}A${r} ${r} 0 0 1 ${W - f} ${endD + r}`;
        p += `V${H - f - r}A${r} ${r} 0 0 1 ${W - f - r} ${H - f}`;
        p += `H${f + r}A${r} ${r} 0 0 1 ${f} ${H - f - r}`;
        p += `V${startD + r}A${r} ${r} 0 0 1 ${f + r} ${startD}Z`;
        return p;
    }

    ShapePath {
        fillColor: Theme.bg
        strokeColor: "transparent"
        strokeWidth: 0
        fillRule: ShapePath.OddEvenFill
        PathSvg { path: frame.svg }
    }
}
