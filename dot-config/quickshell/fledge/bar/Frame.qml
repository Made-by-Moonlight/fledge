import QtQuick
import QtQuick.Shapes
import "../theme"

// The bar edge as one path: a thin strip along the screen edge, and a tab hanging from it per
// section (concave fillet off the strip, straight side, convex corner into the tab's bottom
// edge). Nothing down the sides or along the far edge: windows reach those edges.
// One path on one surface, so strip, tabs and fillets have no joins that could seam.
// The path is drawn for a top bar; a bottom bar mirrors it.
Shape {
    id: frame
    property bool atTop: true
    // Tabs as [left, right] x spans of their bottom edges.
    property var tabs: []

    // CurveRenderer anti-aliases curves without a multisampled fullscreen layer.
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { origin.y: frame.height / 2; yScale: frame.atTop ? 1 : -1 }

    readonly property string svg: {
        const W = width, S = Theme.frame, D = Theme.barHeight, c = Math.min(Theme.tabRadius, (D - S) / 2);
        // Tabs too close for two fillets between them become one tab.
        const spans = [];
        for (const t of [...tabs].sort((a, b) => a[0] - b[0])) {
            const last = spans[spans.length - 1];
            if (last && t[0] - last[1] < 2 * c + 2) last[1] = Math.max(last[1], t[1]);
            else spans.push([t[0], t[1]]);
        }
        // A tab that starts at 0 or ends at the width hangs from that corner: no fillet there.
        const startD = spans.length && spans[0][0] <= 0 ? D : S;

        // Along the strip's (and tabs') lower edge left to right, then back along the screen edge.
        let p = `M0 ${startD}`;
        for (const [L, R] of spans) {
            if (L > 0) p += `H${L - c}A${c} ${c} 0 0 1 ${L} ${S + c}V${D - c}A${c} ${c} 0 0 0 ${L + c} ${D}`;
            if (R < W) p += `H${R - c}A${c} ${c} 0 0 0 ${R} ${D - c}V${S + c}A${c} ${c} 0 0 1 ${R + c} ${S}`;
        }
        p += `H${W}V0H0Z`;
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
