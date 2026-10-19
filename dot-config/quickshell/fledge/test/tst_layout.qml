import QtQuick
import QtTest
import "../settings/Layout.js" as L

TestCase {
    name: "layout"
    // The user's desk (hyprctl monitors -j, 2026-10-19): mm are the unrotated panel's.
    readonly property var acer: ({ key: "desc:Acer", px: [3440, 1440], mm: [800, 350], scale: 1, transform: 0 })
    readonly property var benqL: ({ key: "desc:BenqL", px: [2560, 1440], mm: [600, 340], scale: 1, transform: 1 })
    readonly property var benqR: ({ key: "desc:BenqR", px: [2560, 1440], mm: [600, 340], scale: 1, transform: 3 })

    function r(key, x, y, w, h) { return { key: key, x: x, y: y, w: w, h: h }; }
    function find(rects, key) { return rects.find(q => q.key === key); }
    function overlapping(rects) {
        for (let i = 0; i < rects.length; i++)
            for (let j = i + 1; j < rects.length; j++)
                if (L.overlaps(rects[i], rects[j])) return true;
        return false;
    }
    function touchesAny(rects, key) {
        const a = find(rects, key);
        return rects.some(b => b.key !== key && L.touching(a, b));
    }

    function test_sizes() {
        compare(L.logical(benqL), [1440, 2560]);
        compare(L.physical(benqL), [340, 600]);
        compare(L.logical({ key: "k", px: [3840, 2160], mm: [600, 340], scale: 1.5, transform: 0 }), [2560, 1440]);
        verify(L.trusted(acer));
        verify(!L.trusted({ key: "k", px: [1920, 1080], mm: [0, 0], scale: 1, transform: 0 }));
        // A portrait panel claiming landscape mm: the aspect ratios disagree.
        verify(!L.trusted({ key: "k", px: [1440, 2560], mm: [160, 90], scale: 1, transform: 0 }));
        compare(L.physical({ key: "k", px: [1920, 1080], mm: [0, 0], scale: 1, transform: 0 }), [508, 285.75]);
    }
    function test_user_desk_round_trip() {
        const mons = [acer, benqL, benqR];
        const pos = { "desc:Acer": [0, 0], "desc:BenqL": [-1440, -560], "desc:BenqR": [3440, -560] };
        const rects = L.fromLogical(mons, pos);
        compare(rects.length, 3);
        compare(rects[0].key, "desc:Acer");
        compare(L.problems(rects), []);
        const out = L.toLogical(mons, rects);
        verify(out.ok, out.error);
        for (const k of Object.keys(pos)) {
            verify(Math.abs(out.pos[k][0] - pos[k][0]) <= 1, k + " x " + out.pos[k][0]);
            verify(Math.abs(out.pos[k][1] - pos[k][1]) <= 1, k + " y " + out.pos[k][1]);
        }
        compare(benqL.transform, 1);
        compare(benqR.transform, 3);
    }
    // Along the shared edge exact logical px; across it the mm offset at the parent's density.
    function test_physical_alignment() {
        const out = L.toLogical([acer, benqL], [r("desc:Acer", 0, 0, 800, 350), r("desc:BenqL", -340, -131, 340, 600)]);
        verify(out.ok, out.error);
        compare(out.pos["desc:Acer"], [0, 0]);
        compare(out.pos["desc:BenqL"], [-1440, Math.round(-131 * 3440 / 800)]);
        compare(out.pos["desc:BenqL"][1], -563);
    }
    function test_mixed_scale() {
        const small = { key: "desc:Small", px: [1920, 1080], mm: [530, 300], scale: 1, transform: 0 };
        const big = { key: "desc:Big", px: [3840, 2160], mm: [600, 340], scale: 1.5, transform: 0 };
        const out = L.toLogical([small, big], [r("desc:Small", 0, 0, 530, 300), r("desc:Big", 530, 0, 600, 340)]);
        verify(out.ok, out.error);
        compare(out.pos["desc:Big"][0], 1920);
    }
    // The cursor can't cross a corner.
    function test_corner_not_touching() {
        const a = r("desc:Acer", 0, 0, 800, 350), b = r("desc:BenqR", 800, 350, 340, 600);
        verify(!L.touching(a, b));
        const p = L.problems([a, b]);
        verify(p.length > 0);
        verify(p.some(m => m.indexOf("BenqR") >= 0 && m.indexOf("doesn't touch") >= 0), p.join("; "));
    }
    function test_overlap_pushout() {
        const rects = [r("desc:Acer", 0, 0, 800, 350), r("desc:BenqR", 900, 0, 340, 600)];
        const out = L.drag(rects, "desc:BenqR", 230, -125, 12);
        verify(!overlapping(out));
        verify(L.touching(find(out, "desc:Acer"), find(out, "desc:BenqR")));
        compare(rects[1].x, 900);   // inputs untouched
    }
    function test_float_settles() {
        const out = L.settle([r("desc:Acer", 0, 0, 800, 350), r("desc:BenqR", 1000, -131, 340, 600)], "desc:BenqR");
        verify(L.touching(find(out, "desc:Acer"), find(out, "desc:BenqR")));
        compare(L.problems(out), []);
    }
    // Enabled again after the layout changed: its saved place is now taken.
    function test_enable_into_overlap() {
        const rects = [r("desc:Acer", 0, 0, 800, 350), r("desc:BenqL", -340, -131, 340, 600), r("desc:BenqR", 700, -100, 340, 600)];
        const out = L.settle(rects, "desc:BenqR");
        verify(!overlapping(out));
        verify(touchesAny(out, "desc:BenqR"));
        compare(L.problems(out), []);
    }
    function test_rotate_about_centre() {
        // Alone, settle has nothing to do: the centre stays exactly.
        const lone = L.rotate([r("desc:Acer", 0, 0, 800, 350)], "desc:Acer", 350, 800);
        const a = lone[0];
        compare([a.w, a.h], [350, 800]);
        compare([a.x + a.w / 2, a.y + a.h / 2], [400, 175]);
        // Between the BenQs it may move, but ends up placed properly.
        const out = L.rotate([r("desc:Acer", 0, 0, 800, 350), r("desc:BenqL", -340, -131, 340, 600), r("desc:BenqR", 800, -131, 340, 600)],
                             "desc:Acer", 350, 800);
        verify(!overlapping(out));
        verify(touchesAny(out, "desc:Acer"));
    }
    // Each monitor touches two placed neighbours, one per axis.
    function test_grid_cycle() {
        const m = k => ({ key: k, px: [1920, 1080], mm: [530, 300], scale: 1, transform: 0 });
        const out = L.toLogical([m("A"), m("B"), m("C"), m("D")],
                                [r("A", 0, 0, 530, 300), r("B", 530, 0, 530, 300), r("C", 0, 300, 530, 300), r("D", 530, 300, 530, 300)]);
        verify(out.ok, out.error);
        compare(out.pos, { A: [0, 0], B: [1920, 0], C: [0, 1080], D: [1920, 1080] });
    }
    function test_refused() {
        const two = [acer, benqR];
        let out = L.toLogical(two, [r("desc:Acer", 0, 0, 800, 350), r("desc:BenqR", 700, 0, 340, 600)]);
        verify(!out.ok);
        compare(out.error, "Acer and BenqR overlap");
        out = L.toLogical(two, [r("desc:Acer", 0, 0, 800, 350), r("desc:BenqR", 900, 0, 340, 600)]);
        verify(!out.ok);
        compare(out.error, "Acer doesn't touch another monitor");
        // Same mm width, but C is twice A's logical width: D can't sit flush against both B and C.
        const hd = k => ({ key: k, px: [1920, 1080], mm: [530, 300], scale: 1, transform: 0 });
        const uhd = k => ({ key: k, px: [3840, 2160], mm: [530, 298], scale: 1, transform: 0 });
        out = L.toLogical([hd("A"), hd("B"), uhd("C"), uhd("D")],
                          [r("A", 0, 0, 530, 300), r("B", 530, 0, 530, 300), r("C", 0, 300, 530, 298), r("D", 530, 300, 530, 298)]);
        verify(!out.ok);
        compare(out.error, "D can't line up with both C and B");
    }
    // A hand-set gap: still drawn, with the problem named, rather than a throw.
    function test_broken_layout_draws() {
        const rects = L.fromLogical([acer, benqL, benqR], { "desc:Acer": [0, 0], "desc:BenqL": [-1540, -560], "desc:BenqR": [3440, -560] });
        compare(rects.length, 3);
        const p = L.problems(rects);
        verify(p.length > 0);
        verify(p.some(m => m.indexOf("BenqL") >= 0), p.join("; "));
    }
    function test_fit() {
        const f = L.fit([r("A", 0, 0, 800, 350), r("B", -340, -131, 340, 600)], 1000, 600, 20);
        // Bounding box 1140 x 600 mm: width-bound.
        fuzzyCompare(f.scale, 960 / 1140, 1e-9);
        fuzzyCompare(f.ox + -340 * f.scale, 20, 1e-9);
        fuzzyCompare(f.oy + -131 * f.scale + 600 * f.scale / 2, 300, 1e-9);
    }
}
