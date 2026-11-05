#!/usr/bin/env python3
"""Run in the test VM: python3 .../test/test-bluetooth-agent.py."""
import importlib.util
from pathlib import Path
import unittest
import sys
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location(
    "agent", Path(__file__).resolve().parents[1] / "bluetooth/agent.py")
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)
sys.modules["agent"] = agent


class PairingTests(unittest.TestCase):
    def setUp(self):
        for target in ("emit", "GLib.source_remove", "GLib.timeout_add_seconds",
                       "dbus.service.Object.__init__", "dbus.Interface"):
            p = patch("agent." + target)
            value = p.start()
            self.addCleanup(p.stop)
            if target == "dbus.service.Object.__init__":
                value.return_value = None
        self.a = agent.Agent(Mock())
        self.reply, self.error = Mock(), Mock()

    def request(self, kind):
        self.a.prompt(kind, "/device", self.reply, self.error)
        return self.a.serial

    def test_confirmation_requires_explicit_accept(self):
        self.a.RequestConfirmation("/device", 42, self.reply, self.error)
        agent.emit.assert_called_with(event="prompt", id=1, kind="confirm",
                                      name=unittest.mock.ANY, address=unittest.mock.ANY,
                                      code="000042")
        self.reply.assert_not_called()
        self.a.respond({"id": 1, "accept": True})
        self.reply.assert_called_once_with()

    def test_stale_response_cannot_accept_new_request(self):
        old = self.request("confirm")
        self.a.cancel()
        new = self.request("confirm")
        self.a.respond({"id": old, "accept": True})
        self.reply.assert_not_called()
        self.assertEqual(self.a.serial, new)

    def test_pin_preserves_leading_zeroes(self):
        request = self.request("pin")
        self.a.respond({"id": request, "accept": True, "value": "0042"})
        self.reply.assert_called_once_with("0042")

    def test_passkey_rejects_invalid_input(self):
        request = self.request("passkey")
        for value in ("", "1234567", "-1", "１２３", "12a", 123):
            self.a.respond({"id": request, "accept": True, "value": value})
        self.reply.assert_not_called()
        self.a.respond({"id": request, "accept": True, "value": "000042"})
        self.reply.assert_called_once_with(42)

    def test_pin_rejects_empty_and_long_input(self):
        request = self.request("pin")
        for value in ("", "x" * 17, None):
            self.a.respond({"id": request, "accept": True, "value": value})
        self.reply.assert_not_called()

    def test_cancel_rejects_and_cancels_pairing(self):
        self.request("authorize")
        device = self.a.device = Mock()
        self.a.cancel()
        self.error.assert_called_once()
        device.CancelPairing.assert_called_once()
        self.assertIsNone(self.a.pending)

    def test_timeout_rejects(self):
        self.request("pin")
        self.assertFalse(self.a.expire())
        self.error.assert_called_once()

    def test_second_prompt_does_not_replace_first(self):
        original = self.request("pin")
        reject = Mock()
        self.a.prompt("confirm", "/other", Mock(), reject)
        reject.assert_called_once()
        self.assertEqual(self.a.serial, original)
        self.assertEqual(self.a.pending[0], "pin")

    def test_display_updates_keep_zero_padding(self):
        self.a.DisplayPasskey("/device", 42, 2)
        self.assertEqual(self.a.pending[0], "display")
        self.assertEqual(agent.emit.call_args.kwargs["code"], "000042")
        self.assertEqual(agent.emit.call_args.kwargs["entered"], 2)
        self.a.DisplayPasskey("/device", 42, 3)
        self.assertEqual(agent.emit.call_args.kwargs["entered"], 3)

    def test_old_pair_result_does_not_clear_new_pair(self):
        self.a.operation = 2
        device = self.a.device = Mock()
        self.a.finished(1, "old operation failed")
        self.assertIs(self.a.device, device)
        agent.emit.assert_not_called()


if __name__ == "__main__":
    unittest.main()
