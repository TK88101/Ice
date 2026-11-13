"""Rules of zh_check.py (plan 2026-11-13-zh-hant, T2b), on made-up texts."""
import importlib.util
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("zh_check", os.path.join(HERE, "zh_check.py"))
zh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(zh)


class UntranslatedTest(unittest.TestCase):
    keys = {"Show on hover", "Quit Ice", "1"}

    def test_chinese_passes(self):
        self.assertEqual(zh.untranslated(["指標停留時顯示", "結束 Ice"], self.keys), [])

    def test_an_english_key_is_reported(self):
        self.assertEqual(zh.untranslated(["Show on hover"], self.keys), ["Show on hover"])

    def test_english_words_not_in_the_catalog_are_reported(self):
        self.assertEqual(zh.untranslated(["Launch at login"], self.keys), ["Launch at login"])

    def test_product_names_numbers_and_symbols_pass(self):
        self.assertEqual(zh.untranslated(["Ice", "Ice Bar", "English", "1", "0.2", "⌘", "•", "12%"], self.keys), [])

    def test_other_apps_names_pass(self):
        self.assertEqual(zh.untranslated(["Dropbox"], self.keys, foreign={"Dropbox"}), [])

    def test_short_codes_pass_but_are_not_language(self):
        self.assertEqual(zh.untranslated(["OK"], set()), [])

    def test_catalog_values_read(self):
        catalog = {"strings": {"Quit": {"localizations": {"zh-Hant": {"stringUnit": {"value": "結束"}}}}, "X": {}}}
        with tempfile.NamedTemporaryFile("w", suffix=".xcstrings", delete=False) as handle:
            json.dump(catalog, handle)
        values, keys = zh.catalog_values(handle.name)
        os.unlink(handle.name)
        self.assertEqual(values, {"結束"})
        self.assertEqual(keys, {"Quit", "X"})


if __name__ == "__main__":
    unittest.main()
