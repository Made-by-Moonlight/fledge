.pragma library
function size(bytes) {
    const u = ["B", "KiB", "MiB", "GiB", "TiB"];
    let n = bytes, i = 0;
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i >= 3 ? n.toFixed(1) : Math.round(n)) + " " + u[i];
}
