.pragma library
// Mirrors cachyos/install/lib/answers.sh (valid_username, valid_hostname,
// valid_mount_path). install-cachyos.sh re-checks all of it, so a mismatch
// fails the install loudly rather than writing a bad system.

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
    // Hidden folders (~/.config …) belong to the desktop.
    if (parts.some(c => c.startsWith("."))) return "Hidden folders can't be used";
    // ~/proj holds the staged repo the dotfiles link into; a mount would hide it.
    // Its ancestors (/home, a whole home) are refused below.
    if (parts[0] === "home" && parts[2] === "proj") return "~/proj holds fledge's own files";
    if (system.includes(parts[0])) return "That's a system folder";
    if (parts[0] === "home" && parts.length < 3) return "Pick a folder inside the home folder";
    if (["mnt", "srv", "media", "opt"].includes(parts[0]) && parts.length < 2) return "Pick a folder inside " + abs;
    return "";
}

// Index of the first entry ({ skipped, valid }) that is neither skipped nor
// valid, else -1. Review uses it to re-check every earlier step before erasing.
function firstInvalid(list) { return list.findIndex(s => !s.skipped && !s.valid); }
