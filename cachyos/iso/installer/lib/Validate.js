.pragma library
// Mirrors cachyos/install/lib/answers.sh (valid_username, valid_mount_path) and
// cachyos/iso/lib/mbm.sh (valid_hostname). install-cachyos.sh re-checks all of
// it, so a mismatch fails the install loudly rather than writing a bad system.

const reserved = /^(root|bin|daemon|mail|ftp|http|nobody|dbus|polkitd|git|sddm|systemd-.*)$/;
function username(u) { return /^[a-z_][a-z0-9_-]{0,31}$/.test(u) && !reserved.test(u); }
function hostname(h) { return /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(h); }
function expand(p, home) { return p.replace(/^~(?=\/|$)/, home); }

const system = ["boot", "efi", "usr", "var", "etc", "bin", "sbin", "lib", "lib64", "root", "run", "proc", "sys", "dev", "tmp", "swap"];
// "" when p (absolute, or ~/...) is a usable data mountpoint, else why not.
function mountPath(p, home) {
    const abs = expand(p, home);
    if (!/^\/[A-Za-z0-9._\/-]+$/.test(abs)) return "Use a folder like ~/storage or /data (letters, digits, . _ -)";
    if (/\/\/|\/$|(^|\/)\.\.?(\/|$)/.test(abs)) return "That folder path isn't clean";
    const parts = abs.split("/").slice(1);
    if (system.includes(parts[0])) return "That's a system folder";
    if (parts[0] === "home" && parts.length < 3) return "Pick a folder inside the home folder";
    if (["mnt", "srv", "media", "opt"].includes(parts[0]) && parts.length < 2) return "Pick a folder inside " + abs;
    return "";
}
