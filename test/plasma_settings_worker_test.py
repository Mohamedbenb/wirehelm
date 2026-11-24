import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "assets/desktop/plasma_settings.py"
SPEC = importlib.util.spec_from_file_location("plasma_settings", SOURCE)
SETTINGS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SETTINGS)


def screen(scale=1.25):
    return {"id": 2, "name": "HDMI-A-3", "connected": True, "enabled": True,
            "priority": 1, "rotation": 1, "scale": scale,
            "pos": {"x": 0, "y": 0}, "currentModeId": "7",
            "modes": [{"id": "7", "refreshRate": 60, "size": {"width": 1920, "height": 1080}}]}


def request(**overrides):
    return {"id": 2, "name": "HDMI-A-3", "enabled": True, "mode": "7",
            "scale": 1.5, "rotation": 1, "x": 0, "y": 0, **overrides}


class DisplayRestoreTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.enterContext(patch.dict(os.environ, {"XDG_RUNTIME_DIR": directory.name}))
        self.snapshot = Path(directory.name) / "wirehelm-display/restore.json"
        self.now = self.enterContext(patch.object(SETTINGS.time, "monotonic", return_value=100))
        self.outputs = self.enterContext(patch.object(SETTINGS, "displays"))
        self.apply = self.enterContext(patch.object(SETTINGS, "apply"))

    def test_last_enabled_output_cannot_be_disabled(self):
        with self.assertRaisesRegex(ValueError, "at least one display"):
            SETTINGS.edits([screen()], request(enabled=False))

    def test_apply_is_immediate_and_restore_is_available_after_reopening(self):
        self.outputs.side_effect = [[screen()], [screen(1.5)], [screen(1.5)],
                                    [screen(1.5)], [screen(1.5)], [screen()]]
        applied = SETTINGS.apply_display(request())
        self.assertEqual(applied["outputs"], [screen(1.5)])
        self.assertEqual(applied["restoreMs"], 15000)
        self.apply.assert_called_once_with(["output.2.scale.1.5"])
        reopened = SETTINGS.read_displays()
        self.assertEqual(reopened["restoreToken"], applied["restoreToken"])
        restored = SETTINGS.restore_display(applied["restoreToken"])
        self.assertEqual(restored, {"outputs": [screen()]})
        self.apply.assert_called_with(["output.2.scale.1.25"])
        self.assertFalse(self.snapshot.exists())

    def test_expiry_leaves_the_new_display_settings_applied(self):
        self.outputs.side_effect = [[screen()], [screen(1.5)], [screen(1.5)], [screen(1.5)]]
        applied = SETTINGS.apply_display(request())
        self.now.return_value = 116
        self.assertEqual(SETTINGS.read_displays(), {"outputs": [screen(1.5)]})
        with self.assertRaisesRegex(ValueError, "no longer be restored"):
            SETTINGS.restore_display(applied["restoreToken"])
        self.apply.assert_called_once_with(["output.2.scale.1.5"])
        self.assertFalse(self.snapshot.exists())

    def test_later_external_changes_invalidate_restore(self):
        self.outputs.side_effect = [[screen()], [screen(1.5)], [screen(1.75)]]
        applied = SETTINGS.apply_display(request())
        with self.assertRaisesRegex(ValueError, "no longer be restored"):
            SETTINGS.restore_display(applied["restoreToken"])
        self.apply.assert_called_once_with(["output.2.scale.1.5"])

    def test_apply_failure_rolls_back_immediately(self):
        self.outputs.side_effect = [[screen()], [screen(1.5)]]
        self.apply.side_effect = [RuntimeError("KScreen failed"), None]
        with self.assertRaisesRegex(RuntimeError, "KScreen failed"):
            SETTINGS.apply_display(request())
        self.apply.assert_called_with(["output.2.scale.1.25"])
        self.assertFalse(self.snapshot.exists())


class TextSizeTest(unittest.TestCase):
    def setUp(self):
        self.fonts = {
            ("General", "font"): "Noto Sans,14,-1,5,400,0,0,0,0,0",
            ("General", "menuFont"): "Custom Sans,10,-1,5,600,1,0,0,0,0",
        }
        self.notifications = []
        self.rejected = None

        def native(command, *args):
            if command == "busctl":
                self.notifications.append(args[-1])
                return ""
            key = (args[args.index("--group") + 1], args[args.index("--key") + 1])
            if command == "kreadconfig6":
                return self.fonts.get(key, "") + "\n"
            if key == self.rejected:
                self.rejected = None
                raise RuntimeError("write rejected")
            if args[-1] == "--delete":
                self.fonts.pop(key, None)
            else:
                self.fonts[key] = args[-1]
            return ""

        self.enterContext(patch.object(SETTINGS, "run", side_effect=native))

    def test_applies_every_role_even_when_general_already_matches(self):
        self.assertFalse(SETTINGS.text_size({})["sizesMatch"])
        reply = SETTINGS.text_size({"size": 14})
        self.assertTrue(reply["sizesMatch"])
        self.assertEqual(self.fonts["General", "menuFont"],
                         "Custom Sans,14,-1,5,600,1,0,0,0,0")
        self.assertTrue(self.fonts["General", "fixed"].startswith("Hack,14,-1,"))
        self.assertTrue(self.fonts["General", "smallestReadableFont"].startswith("Noto Sans,12,-1,"))
        for role in [("General", "toolBarFont"), ("General", "taskbarFont"), ("WM", "activeFont")]:
            self.assertEqual(self.fonts[role].split(",")[1], "14")
        self.assertTrue(SETTINGS.text_size({})["sizesMatch"])
        self.assertEqual(self.notifications, ["refreshFonts"])

    def test_failed_write_restores_previous_font_values_and_defaults(self):
        previous = self.fonts.copy()
        self.rejected = ("WM", "activeFont")
        with self.assertRaisesRegex(RuntimeError, "write rejected"):
            SETTINGS.text_size({"size": 15})
        self.assertEqual(self.fonts, previous)
        self.assertEqual(self.notifications, ["refreshFonts"])


if __name__ == "__main__":
    unittest.main()
