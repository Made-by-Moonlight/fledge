.pragma library
// Match: 0 = no match; higher is better. Prefix (~100) beats substring (~40-80)
// beats scattered subsequence (10-39), so "fir" ranks Firefox above "Font Viewer".
// Scattered letters earn most when they land on word starts (string start, after
// space - _ . or a lower-to-Upper camel boundary), so acronyms work: "vsc" finds
// Visual Studio Code.
function score(query, text) {
    if (!query) return 1;
    const q = query.toLowerCase(), orig = text || "", t = orig.toLowerCase();
    if (t.startsWith(q)) return 100 - Math.min(t.length, 50) / 10;
    const i = t.indexOf(q);
    if (i >= 0) return 60 - i / 10 + (/[\s\-_.]/.test(t[i - 1]) ? 20 : 0);

    const n = t.length, m = q.length;
    if (m > n) return 0;
    const ws = [];
    for (let k = 0; k < n; k++) {
        const p = orig[k - 1], c = orig[k];
        ws.push(k === 0 || /[\s\-_.]/.test(p) || (/[a-z]/.test(p) && /[A-Z]/.test(c)));
    }
    // best[k]: top score matching q[0..j] with q[j] at text position k.
    let best = null;
    for (let j = 0; j < m; j++) {
        const next = new Array(n).fill(-1);
        for (let k = j; k < n; k++) {
            if (t[k] !== q[j]) continue;
            const here = ws[k] ? 3 : 1;
            if (j === 0) { next[k] = here; continue; }
            let b = -1;
            for (let p = j - 1; p < k; p++)
                if (best[p] >= 0) b = Math.max(b, best[p] + (p === k - 1 ? 2 : 0));
            if (b >= 0) next[k] = b + here;
        }
        best = next;
    }
    const top = Math.max(...best);
    if (top < 0) return 0;
    // Max per letter is 5 (consecutive word start); normalise so the result stays below 40.
    return 10 + 28 * Math.min(1, top / (5 * m)) - Math.min(n, 60) / 60;
}
