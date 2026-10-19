import json
import tempfile
import unittest
from pathlib import Path

from cloudgamingctl import load_config, ssh_argv

class SessionControlTests(unittest.TestCase):
    def make_config(self, tmp, **overrides):
        key = Path(tmp) / "ssh-key"
        key.write_text("fixture-only")
        options = {
            "remote_host": "10.77.0.2",
            "remote_user": "cloudgaming",
            "ssh_key": str(key),
            "ssh_port": 22,
        }
        options.update(overrides)
        path = Path(tmp) / "config.json"
        path.write_text(json.dumps(options))
        return path

    def test_control_commands_are_allowlisted(self):
        with tempfile.TemporaryDirectory() as tmp:
            c = load_config(self.make_config(tmp))
            for command in ("start", "stop", "status", "logs"):
                argv = ssh_argv(c, command)
                self.assertIn("StrictHostKeyChecking=yes", argv)
                self.assertIn("BatchMode=yes", argv)
                self.assertEqual(argv[-2:], ["cloudgaming-remote-control", command])
            with self.assertRaises(ValueError):
                ssh_argv(c, "bash -c rm -rf /")

    def test_reject_injected_hosts_and_users(self):
        with tempfile.TemporaryDirectory() as tmp:
            for changes in ({"remote_host": "host;touch /tmp/hack"},
                            {"remote_host": "-oProxyCommand=foo"},
                            {"remote_user": "root;echo x"},
                            {"ssh_port": 99999}):
                with self.subTest(changes=changes):
                    with self.assertRaises(ValueError):
                        load_config(self.make_config(tmp, **changes))

    def test_missing_identity_denied(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                load_config(self.make_config(tmp, ssh_key="/unavailable/secret"))

if __name__ == "__main__":
    unittest.main()
