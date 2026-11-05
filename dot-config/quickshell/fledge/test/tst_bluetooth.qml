import QtQuick
import QtTest
import "../services/Bluetooth.js" as Devices

TestCase {
    name: "bluetoothDevices"
    function device(name, address, paired, connected) {
        return {name: name, address: address || "AA:BB:CC:DD:EE:FF", paired: !!paired, connected: !!connected};
    }
    function test_address_aliases_are_unnamed() {
        for (const alias of ["", "  ", "AA-BB-CC-DD-EE-FF", "aa:bb:cc:dd:ee:ff"]) {
            const d = device(alias);
            verify(!Devices.hasName(d));
            compare(Devices.name(d), d.address);
        }
        verify(Devices.hasName(device(" JBL Live Pro 4 ")));
        compare(Devices.name(device(" JBL Live Pro 4 ")), "JBL Live Pro 4");
    }
    function test_named_device_not_buried_by_addresses() {
        const devices = [];
        for (let i = 0; i < 20; i++) devices.push(device("", "00:00:00:00:00:" + i));
        const jbl = device("JBL Live Pro 4");
        devices.push(jbl);
        devices.sort(Devices.compare);
        compare(devices[0], jbl);
        compare(Devices.visible(devices, false, ""), [jbl]);
        compare(Devices.visible(devices, true, "").length, 21);
    }
    function test_connected_paired_and_pairing_stay_visible() {
        const connected = device("", "01", false, true);
        const paired = device("", "02", true);
        const pairing = device("", "03");
        const unknown = device("", "04");
        compare(Devices.visible([unknown, pairing, paired, connected], false, "03"), [pairing, paired, connected]);
        const sorted = [unknown, device("JBL"), paired, connected].sort(Devices.compare);
        compare(sorted[0], connected);
        compare(sorted[1], paired);
    }
    function test_no_named_devices_are_truncated() {
        const devices = [];
        for (let i = 0; i < 20; i++) devices.push(device("Speaker " + i));
        compare(Devices.visible(devices, false, "").length, 20);
    }
}
