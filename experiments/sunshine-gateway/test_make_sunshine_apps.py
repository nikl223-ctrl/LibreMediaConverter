import unittest

from make_sunshine_apps import merge_apps, APPS


class CloudGamingAppTests(unittest.TestCase):
    def test_creates_two_selectable_moonlight_applications(self):
        result = merge_apps({})
        apps = result["apps"]
        self.assertEqual([x["name"] for x in apps], ["GeForce NOW", "Xbox Cloud Gaming"])
        self.assertEqual(apps[0]["cmd"], "$(HOME)/.local/bin/cloudgaming-app geforce-now")
        self.assertEqual(apps[1]["cmd"], "$(HOME)/.local/bin/cloudgaming-app xbox-cloud")
        self.assertFalse(apps[0]["auto-detach"])

    def test_preserves_other_sunshine_applications_and_global_environment(self):
        initial = {
            "env": {"PATH": "/usr/bin"},
            "apps": [{"name": "Existing Game", "cmd": "game"}, {"name": "GeForce NOW", "cmd": "wrong"}],
            "other-key": "keep",
        }
        result = merge_apps(initial)
        self.assertEqual(result["env"], initial["env"])
        self.assertEqual(result["other-key"], "keep")
        self.assertEqual(result["apps"][0]["name"], "Existing Game")
        self.assertEqual(len([x for x in result["apps"] if x["name"] == "GeForce NOW"]), 1)

    def test_repeated_merging_is_idempotent(self):
        first = merge_apps({})
        self.assertEqual(first, merge_apps(first))

    def test_rejects_invalid_structure(self):
        for bad in ([], {"apps": {}}, {"apps": "wrong"}):
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    merge_apps(bad)


if __name__ == "__main__":
    unittest.main()
