// BlueZ sometimes uses the address, with hyphens, as the device's name.
function hasName(device) {
    const name = (device.name || "").trim();
    const normalize = value => value.replace(/[:-]/g, "").toUpperCase();
    return name !== "" && normalize(name) !== normalize(device.address || "");
}

function name(device) {
    return hasName(device) ? device.name.trim() : (device.address || "Unknown device");
}

function compare(a, b) {
    return (b.connected - a.connected) || (b.paired - a.paired)
        || (Number(hasName(b)) - Number(hasName(a))) || name(a).localeCompare(name(b));
}

function visible(devices, showUnnamed, pairingAddress) {
    return devices.filter(d => showUnnamed || hasName(d) || d.paired || d.connected || d.address === pairingAddress);
}
