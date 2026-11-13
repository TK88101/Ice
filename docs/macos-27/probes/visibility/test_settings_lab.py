"""Unit tests of the settings pass's runner (plan 2026-11-12-settings-cleanup,
section 6): the pure helpers of settings_lab.py and settings_cases.py. Run by
test-settings.sh: python3 -I test_settings_lab.py. No side effects."""
import importlib.util
import json
import os
import plistlib
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


lab = load("settings_lab", "settings_lab.py")
cases = load("settings_cases", "settings_cases.py")


def snapshot(**fields):
    base = {"event": "snapshot", "lengthApplied": False, "isIceBarOffered": False, "isIceBarPresented": False, "roster": []}
    base.update(fields)
    return base


class ReportTests(unittest.TestCase):
    def test_a_torn_last_line_is_left_out(self):
        text = json.dumps({"event": "start"}) + "\n" + '{"event": "snaps'
        self.assertEqual(lab.parse_report(text), [{"event": "start"}])

    def test_complete_lines_are_all_read(self):
        text = "".join(json.dumps({"seq": index}) + "\n" for index in range(3))
        self.assertEqual([event["seq"] for event in lab.parse_report(text)], [0, 1, 2])

    def test_the_last_snapshot_is_the_latest_one(self):
        events = [snapshot(pass_=1), {"event": "status"}, snapshot(pass_=2), {"event": "length"}]
        self.assertEqual(lab.last_snapshot(events)["pass_"], 2)

    def test_no_snapshot_yet_is_none(self):
        self.assertIsNone(lab.last_snapshot([{"event": "start"}]))

    def test_hidden_rest_needs_length_offer_and_the_members(self):
        member = {"identifier": "m"}
        self.assertTrue(lab.is_hidden_rest(snapshot(lengthApplied=True, isIceBarOffered=True, roster=[member])))
        self.assertFalse(lab.is_hidden_rest(snapshot(lengthApplied=False, isIceBarOffered=True, roster=[member])))
        self.assertFalse(lab.is_hidden_rest(snapshot(lengthApplied=True, isIceBarOffered=False, roster=[member])))
        self.assertFalse(lab.is_hidden_rest(snapshot(lengthApplied=True, isIceBarOffered=True, roster=[])))
        self.assertTrue(lab.is_hidden_rest(snapshot(lengthApplied=True, isIceBarOffered=True, roster=[member, member]), 2))
        self.assertFalse(lab.is_hidden_rest(None))


class SettingsTests(unittest.TestCase):
    def test_a_hotkey_is_stored_as_ice_stores_it(self):
        self.assertEqual(lab.hotkey_data(105, 15), b"[105,15]")

    def test_the_plist_keeps_each_value_s_type(self):
        read = plistlib.loads(lab.settings_plist({"A": True, "B": 2, "C": 0.5, "D": b"x", "E": {"k": b"y"}}))
        self.assertIs(read["A"], True)
        self.assertEqual((read["B"], read["C"], read["D"], read["E"]["k"]), (2, 0.5, b"x", b"y"))

    def test_a_case_s_settings_go_over_the_base(self):
        merged = lab.merged_settings({"ShowOnClick": False, "RehideInterval": 2.0})
        self.assertFalse(merged["ShowOnClick"])
        self.assertTrue(merged["UseIceBar"])
        self.assertEqual(merged["RehideInterval"], 2.0)
        self.assertTrue(lab.BASE_SETTINGS["ShowOnClick"], "the base is not changed")

    def test_the_appearance_is_stored_as_json_data_with_every_part(self):
        stored = cases.appearance(cases.partial(tint=cases.RED), shape=2, inset=False)
        decoded = json.loads(stored["MenuBarAppearanceConfigurationV2"])
        self.assertEqual(decoded["shapeKind"], 2)
        self.assertFalse(decoded["isInset"])
        self.assertEqual(decoded["staticConfiguration"]["tintKind"], 1)
        self.assertEqual(decoded["staticConfiguration"]["tintColor"]["components"], [1.0, 0.0, 0.0, 1.0])
        self.assertEqual(set(decoded), {
            "lightModeConfiguration", "darkModeConfiguration", "staticConfiguration", "shapeKind",
            "fullShapeInfo", "splitShapeInfo", "isInset", "isDynamic",
        })

    def test_a_gradient_is_tint_kind_two(self):
        self.assertEqual(cases.partial(gradient=[(cases.BLUE, 0.0), (cases.GREEN, 1.0)])["tintKind"], 2)
        self.assertEqual(cases.partial()["tintKind"], 0)

    def test_the_red_square_is_a_png(self):
        self.assertTrue(cases.red_png().startswith(b"\x89PNG\r\n\x1a\n"))


class GuardTests(unittest.TestCase):
    def test_the_release_ice_and_a_lab_copy_are_both_an_ice_running(self):
        lines = [
            "/Applications/Ice.app/Contents/MacOS/Ice",
            "/Users/x/IceReverse-evidence/r-s6/stage/Ice.app/Contents/MacOS/IceLab20261112s6",
            "/Applications/Safari.app/Contents/MacOS/Safari",
            "/usr/bin/IceLabNot/thing",
        ]
        self.assertEqual(lab.running_ice(lines), lines[:2])

    def test_nothing_running_is_empty(self):
        self.assertEqual(lab.running_ice(["/bin/zsh", "/usr/sbin/cfprefsd"]), [])

    def test_only_this_pass_s_identity_is_a_lab_id(self):
        self.assertTrue(lab.is_lab_id("com.icespike4.lab.r20261112-200049.s6"))
        self.assertFalse(lab.is_lab_id("com.jordanbaird.Ice"))
        self.assertFalse(lab.is_lab_id("com.icespike4.lab.r20261112-200049.free"))


class JudgingTests(unittest.TestCase):
    def test_a_verdict_passes_only_when_every_check_holds(self):
        self.assertEqual(lab.verdict([("a", True), ("b", 1)])["result"], "pass")
        failed = lab.verdict([("a", True), ("b", False)])
        self.assertEqual((failed["result"], failed["failed"]), ("fail", ["b"]))

    def test_no_check_at_all_is_not_a_failure_of_one(self):
        self.assertEqual(lab.verdict([])["failed"], [])

    def test_the_panel_is_the_ice_bar_window_on_screen(self):
        windows = [
            {"title": "General", "onScreen": True, "bounds": [0, 0, 900, 600]},
            {"title": "Ice Bar", "onScreen": False, "bounds": [0, 0, 42, 43]},
            {"title": "Ice Bar", "onScreen": True, "bounds": [10, 34, 42, 43]},
        ]
        self.assertEqual(lab.panel_of(windows)["bounds"], [10, 34, 42, 43])
        self.assertIsNone(lab.panel_of(windows[:2]))

    def test_a_panel_is_clamped_to_the_screen(self):
        self.assertEqual(cases.clamped_mid(992, 42), 992)
        self.assertEqual(cases.clamped_mid(5, 42), 21)
        self.assertEqual(cases.clamped_mid(1725, 42), cases.SCREEN_WIDTH - 21)

    def test_near_is_within_two_points_and_never_for_nothing(self):
        self.assertTrue(cases.near(100, 101.9))
        self.assertFalse(cases.near(100, 102.1))
        self.assertFalse(cases.near(None, 100))

    def test_a_channel_dominates_when_it_rose_more_than_the_others(self):
        self.assertTrue(cases.dominant([26.6, -2.0, -19.8], 0))
        self.assertFalse(cases.dominant([3.3, 1.1, 3.9], 0))
        self.assertTrue(cases.dominant([-14.5, -4.5, 16.0], 2))

    def test_shift_is_per_channel_from_the_untouched_bar(self):
        self.assertEqual(cases.shift({"r": [10.0, 20.0, 30.0]}, {"r": [9.0, 22.0, 30.0]}, "r"), [1.0, -2.0, 0.0])

    def test_every_pane_names_what_is_offered_and_what_is_not(self):
        self.assertEqual(list(cases.PANES), ["General", "Menu Bar Appearance", "Hotkeys", "Advanced", "About"])
        for pane, expected in cases.PANES.items():
            self.assertFalse(set(expected["present"]) & set(expected["absent"]), pane)

    def test_every_case_has_a_name_and_a_description(self):
        for name, function in cases.CASES.items():
            self.assertTrue(function.__doc__, name)


if __name__ == "__main__":
    unittest.main()


class IceCommandTest(unittest.TestCase):
    def test_lab_ice_is_english_whatever_its_domain_holds(self):
        command = lab.ice_command("/x/Ice", ["-Extra", "1"])
        index = command.index("-AppleLanguages")
        self.assertEqual(command[index + 1], "(en)")
        self.assertEqual(command[0], "/x/Ice")
        self.assertEqual(command[-2:], ["-Extra", "1"])

