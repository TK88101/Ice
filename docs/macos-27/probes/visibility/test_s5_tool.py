"""Unit tests of s5-tool.py (plan 2026-11-12-s5-owner-acceptance, D7): the
sitting's verdict on synthetic reports and steps -- every clause holding,
failing, skipped and not reached -- and the store's difference. Run by
test-s5.sh: python3 -I test_s5_tool.py. Side effects: a temporary directory,
removed."""
import importlib.util
import json
import os
import shutil
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


s5 = load("s5tool", "s5-tool.py")
fixtures = load("labtooltests", "test_lab_tool.py")
Report, member = fixtures.Report, fixtures.member

ICE = "com.icespike4.lab.r1"
HELPER = "vz-s5-1"
T = "com.icespike4.target"
OWN = {"namespace": "com.example.app", "identifier": "Item-0"}
BAR = [{"namespace": "com.example.a", "identifier": "x"}, OWN, {"namespace": "com.example.b", "identifier": ""}]
ICE_ITEM = {"namespace": ICE, "identifier": "Ice.ControlItem.Visible"}


def own_member(**fields):
    entry = dict(member(OWN["identifier"]), namespace=OWN["namespace"])
    entry.update(fields)
    return entry


def entries(*members):
    return [{"namespace": m["namespace"], "identifier": m["identifier"]} for m in members]


def rest(report, members, visible, status="verified", **fields):
    """A rest holding `members`, the owner's other items still on the bar."""
    values = dict(
        phase="resting", status=status, lengthSet=True, lengthApplied=True, calibratedHiddenLength=736, isIceBarOffered=True,
        roster=members, cells=[dict(e, disabled=False) for e in entries(*members)],
        checks=[dict(e, outcome="hidden") for e in entries(*members)],
        cacheHidden=entries(*members), cacheVisible=visible + [ICE_ITEM],
    )
    values.update(fields)
    return report.snap(**values)


class Sitting:
    """A whole sitting that passes; each test bends one thing."""

    def __init__(self, own=True, invert=True):
        self.report = Report()
        self.steps = []
        self.own, self.invert = own, invert
        self.bend = {}

    def mark(self, step, **fields):
        self.steps.append(dict(step=step, seq=len(self.report.lines), t=1000.0 + len(self.steps), **fields))

    def answer(self, question, default="y"):
        self.mark("answer", q=question, a=self.bend.get(question, default))

    def build(self):
        r, bend = self.report, self.bend
        helper = member(HELPER)
        without_own = [e for e in BAR if e != OWN]
        r.snap(hiddenBoundaryUsable=False, cacheVisible=BAR + [ICE_ITEM])
        r.snap(cacheVisible=bend.get("startVisible", BAR) + [ICE_ITEM], cacheHidden=bend.get("startHidden", []),
               iconPlacement=bend.get("startPlacement"), roster=bend.get("startRoster", []))
        self.mark("helperUp", id=HELPER)
        held = bend.get("helperRoster", [helper])
        r.snap(roster=held, cacheHidden=entries(helper), cacheVisible=BAR + [ICE_ITEM])
        r.length(736)
        r.status(bend.get("helperStatus", "verified"))
        rest(r, held, BAR, status=bend.get("helperStatus", "verified"))
        if not bend.get("neverPresented"):
            rest(r, held, BAR, isIceBarPresented=True)
        self.answer("helperListed")
        self.answer("helperMenu")
        self.answer("doOwn", "y" if self.own else "s")
        if self.own:
            both = [helper, own_member(**bend.get("ownMember", {}))]
            r.snap(roster=both, blockers=bend.get("blockers", []), cacheHidden=entries(*both), cacheVisible=without_own + [ICE_ITEM])
            self.mark("ownSeen", namespace=OWN["namespace"], identifier=OWN["identifier"])
            r.status(bend.get("ownStatus", "verified"))
            rest(r, both, without_own, status=bend.get("ownStatus", "verified"))
            rest(r, both, without_own, isIceBarPresented=True, cells=bend.get("ownCells", [dict(e, disabled=False) for e in entries(*both)]))
            self.mark("ownName", name="the example item")
            self.answer("ownListed")
            self.answer("ownMenu")
        self.answer("doInvert", "y" if self.invert else "s")
        if self.invert:
            r.length(None)
            r.status(bend.get("invertStatus", "blocked(iconLeftOfDivider)"))
            r.snap(status="blocked(iconLeftOfDivider)", iconPlacement="iconLeftOfDivider", isIceBarOffered=bend.get("offeredWhileBlocked", False),
                   roster=[helper], cacheVisible=BAR + [ICE_ITEM])
            self.answer("paneSays")
            r.length(736)
            if not bend.get("neverBack"):
                r.status("verified")
            self.answer("paneClear")
        if self.own:
            self.answer("itemBack")
        rest(r, [helper], bend.get("endVisible", BAR), completeness=bend.get("endCompleteness", "complete"), **{"pass": bend.get("endPass", 3)})
        self.mark("stopping")
        self.mark("cleanup", **dict(dict(ice=True, domain=True, prefsUnchanged=True, store={"added": [], "removed": [], "changed": 3}),
                                    **bend.get("cleanup", {})))
        return self


class S5ToolTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="s5tool")

    def tearDown(self):
        shutil.rmtree(self.root)

    def judge(self, sitting=None, report_text=None, **bend):
        sitting = sitting or Sitting()
        sitting.bend.update(bend)
        sitting.build()
        with open(os.path.join(self.root, "report.jsonl"), "w") as handle:
            handle.write(sitting.report.text() if report_text is None else report_text)
        with open(os.path.join(self.root, "steps.jsonl"), "w") as handle:
            for entry in sitting.steps:
                handle.write(json.dumps(entry) + "\n")
        return s5.judge(self.root)

    def assert_clause(self, verdict, clause, value, result):
        self.assertEqual(verdict["clauses"][clause], value, verdict["reasons"])
        self.assertEqual(verdict["result"], result, verdict["reasons"])

    # --- the whole sitting ----------------------------------------------------------

    def test_a_sitting_where_every_clause_holds_passes(self):
        verdict = self.judge()
        self.assertEqual(verdict["result"], "pass", verdict["reasons"])
        self.assertEqual(set(verdict["clauses"].values()), {"pass"})
        self.assertEqual(verdict["member"], OWN)
        self.assertIn("3 stored value(s) of other items changed", " ".join(verdict["notes"]))

    def test_skipping_the_own_item_is_partial_and_says_helper_only(self):
        verdict = self.judge(Sitting(own=False))
        self.assert_clause(verdict, "C5", "skipped", "partial")
        self.assertEqual(verdict["clauses"]["C8"], "pass")
        self.assertIn("helper only", " ".join(verdict["notes"]))

    def test_skipping_the_icon_drag_is_partial(self):
        self.assert_clause(self.judge(Sitting(invert=False)), "C6", "skipped", "partial")

    # --- C1, C2: the setup ------------------------------------------------------------

    def test_an_owner_item_left_of_the_divider_at_the_start_is_not_established(self):
        verdict = self.judge(startHidden=[OWN])
        self.assert_clause(verdict, "C1", "notEstablished", "notEstablished")
        self.assertEqual(verdict["clauses"]["C2"], "notReached")

    def test_an_icon_left_of_the_divider_at_the_start_is_not_established(self):
        self.assert_clause(self.judge(startPlacement="iconLeftOfDivider"), "C1", "notEstablished", "notEstablished")

    def test_a_member_before_the_helper_is_not_established(self):
        self.assert_clause(self.judge(startRoster=[own_member()]), "C1", "notEstablished", "notEstablished")

    def test_no_settled_snapshot_within_the_start_limit_is_not_established(self):
        sitting = Sitting()
        for _ in range(250):  # 0.5 s a line: the settled snapshot comes after 120 s
            sitting.report.snap(hiddenBoundaryUsable=False)
        self.assert_clause(self.judge(sitting), "C1", "notEstablished", "notEstablished")

    def test_a_helper_that_never_becomes_the_member_is_not_established(self):
        self.assert_clause(self.judge(helperRoster=[]), "C2", "notEstablished", "notEstablished")

    def test_a_roster_that_is_not_the_helper_alone_is_not_established(self):
        self.assert_clause(self.judge(helperRoster=[member(HELPER), own_member()]), "C2", "notEstablished", "notEstablished")

    def test_a_helper_that_is_not_pressable_is_not_established(self):
        self.assert_clause(self.judge(helperRoster=[member(HELPER, "stacked")]), "C2", "notEstablished", "notEstablished")

    # --- C3, C4: the helper hidden and reachable ----------------------------------------

    def test_an_unverified_rest_fails_and_names_the_status(self):
        verdict = self.judge(helperStatus="notVerified(noReference)")
        self.assert_clause(verdict, "C3", "fail", "fail")
        self.assertIn("notVerified(noReference)", " ".join(verdict["reasons"]))

    def test_a_no_to_the_helper_question_fails(self):
        self.assert_clause(self.judge(helperMenu="n"), "C4", "fail", "fail")

    def test_a_yes_without_the_bar_presented_in_the_report_fails(self):
        self.assert_clause(self.judge(neverPresented=True), "C4", "fail", "fail")

    # --- C5: the owner's item -----------------------------------------------------------

    def test_a_positional_blocker_fails_and_is_named(self):
        verdict = self.judge(blockers=[{"namespace": "com.example.c", "identifier": "shared"}], ownStatus="blocked(positional:1)")
        self.assert_clause(verdict, "C5", "fail", "fail")
        self.assertIn("blocked(positional:1)", " ".join(verdict["reasons"]))

    def test_a_stale_own_member_fails(self):
        self.assert_clause(self.judge(ownMember={"condition": "stale", "pressable": False}), "C5", "fail", "fail")

    def test_a_disabled_cell_fails(self):
        cells = [dict(e, disabled=True) for e in entries(member(HELPER), own_member())]
        self.assert_clause(self.judge(ownCells=cells), "C5", "fail", "fail")

    def test_an_own_item_that_stays_unverified_fails(self):
        self.assert_clause(self.judge(ownStatus="notVerified(unchecked:1)"), "C5", "fail", "fail")

    # --- C6: the icon left of the divider ------------------------------------------------

    def test_no_blocked_status_after_the_drag_fails(self):
        self.assert_clause(self.judge(invertStatus="notVerified(lengthNotApplied)"), "C6", "fail", "fail")

    def test_an_icebar_offered_while_blocked_fails(self):
        self.assert_clause(self.judge(offeredWhileBlocked=True), "C6", "fail", "fail")

    def test_never_verified_again_after_the_drag_back_fails(self):
        self.assert_clause(self.judge(neverBack=True), "C6", "fail", "fail")

    def test_a_no_to_the_pane_question_fails(self):
        self.assert_clause(self.judge(paneSays="n"), "C6", "fail", "fail")

    # --- C7: the cleanup ------------------------------------------------------------------

    def test_changed_release_settings_fail(self):
        self.assert_clause(self.judge(cleanup={"prefsUnchanged": False}), "C7", "fail", "fail")

    def test_a_store_key_added_fails(self):
        self.assert_clause(self.judge(cleanup={"store": {"added": ["status:other::x"], "removed": [], "changed": 0}}), "C7", "fail", "fail")

    def test_an_ice_that_did_not_stop_fails_even_when_the_setup_was_not_established(self):
        self.assert_clause(self.judge(startHidden=[OWN], cleanup={"ice": False}), "C7", "fail", "fail")

    def test_a_sitting_without_a_cleanup_record_fails(self):
        sitting = Sitting().build()
        sitting.steps.pop()
        sitting.build = lambda: sitting
        self.assert_clause(self.judge(sitting), "C7", "fail", "fail")

    # --- C8: the bar's order ----------------------------------------------------------------

    def test_an_order_changed_fails_as_changed_with_both_orders(self):
        verdict = self.judge(endVisible=list(reversed(BAR)))
        self.assert_clause(verdict, "C8", "changed", "fail")
        self.assertEqual(verdict["orderBefore"], BAR)
        self.assertEqual(verdict["orderAfter"], list(reversed(BAR)))

    def test_an_item_not_put_back_is_changed(self):
        self.assert_clause(self.judge(itemBack="n"), "C8", "changed", "fail")

    def test_an_end_snapshot_of_a_pass_begun_before_the_last_answer_is_not_established(self):
        self.assert_clause(self.judge(endPass=2, endVisible=list(reversed(BAR))), "C8", "notEstablished", "partial")

    def test_an_unreadable_store_fails(self):
        self.assert_clause(self.judge(cleanup={"store": {"unreadable": True}}), "C7", "fail", "fail")

    def test_an_incomplete_end_snapshot_leaves_the_order_not_established(self):
        self.assert_clause(self.judge(endCompleteness="incomplete:1"), "C8", "notEstablished", "partial")

    # --- a sitting cut short -------------------------------------------------------------------

    def test_a_sitting_ended_early_fails_and_says_where(self):
        sitting = Sitting().build()
        cut = next(i for i, entry in enumerate(sitting.steps) if entry.get("q") == "doOwn")
        sitting.steps = sitting.steps[:cut] + [dict(step="aborted", seq=5, t=1.0, why="interrupted"), sitting.steps[-1]]
        sitting.build = lambda: sitting
        verdict = self.judge(sitting)
        self.assertEqual(verdict["result"], "fail")
        self.assertEqual(verdict["clauses"]["C5"], "notReached")
        self.assertIn("interrupted", " ".join(verdict["reasons"]))

    def test_a_damaged_report_fails_and_still_judges_the_cleanup(self):
        verdict = self.judge(report_text="nope\n")
        self.assertEqual(verdict["result"], "fail")
        self.assertEqual(verdict["clauses"]["C7"], "pass")
        self.assertEqual(verdict["clauses"]["C1"], "notReached")

    # --- what the runner asks while Ice runs -------------------------------------------------------

    def events(self, sitting=None):
        sitting = (sitting or Sitting()).build()
        path = os.path.join(self.root, "r.jsonl")
        with open(path, "w") as handle:
            handle.write(sitting.report.text())
        return s5.lab.load_report(path), sitting

    def test_predicates(self):
        events, sitting = self.events()
        helper_up = next(e for e in sitting.steps if e["step"] == "helperUp")["seq"]
        self.assertTrue(s5.predicate_holds(events, "settled", []))
        self.assertFalse(s5.predicate_holds(events[:2], "settled", []))
        self.assertTrue(s5.predicate_holds(events, "members", [str(helper_up), "1"]))
        self.assertTrue(s5.predicate_holds(events, "members", [str(helper_up), "2"]))
        self.assertFalse(s5.predicate_holds(events, "members", [str(len(events)), "2"]))
        self.assertTrue(s5.predicate_holds(events, "fresh", [str(len(events) - 1)]))
        self.assertFalse(s5.predicate_holds(events, "fresh", [str(len(events))]))
        self.assertTrue(s5.predicate_holds(events, "verified", ["0"]))
        self.assertTrue(s5.predicate_holds(events, "status", ["0", "blocked(iconLeftOfDivider"]))

    def test_the_new_member_is_the_one_that_is_not_the_helper(self):
        events, sitting = self.events()
        cut = next(e for e in sitting.steps if e.get("q") == "doOwn")["seq"]
        self.assertEqual(s5.new_member(events, cut, HELPER), OWN)
        self.assertIsNone(s5.new_member(events[:cut], cut, HELPER))

    # --- the store ----------------------------------------------------------------------------------

    def test_the_store_difference_leaves_out_the_runs_own_keys(self):
        before = {"TrailingItemPreferredPositions": {"status:a::x": 100.0, "status:b::y": 200.0, "status:gone::z": 1.0}}
        after = {"TrailingItemPreferredPositions": {
            "status:a::x": 108.5, "status:b::y": 200.0, "status:new::w": 5.0,
            "status:vzhelper::vz-s5-1": 600.0, "status:com.icespike4.lab.r1::Ice.ControlItem.Visible": 300.0,
        }}
        found = s5.store_difference(before, after, ["vz-s5-1", "com.icespike4.lab.r1"])
        self.assertEqual(found, {"added": ["status:new::w"], "removed": ["status:gone::z"], "changed": 1})

    def test_an_unreadable_store_is_said(self):
        self.assertEqual(s5.store_difference({"unreadable": True}, {}, []), {"unreadable": True})


if __name__ == "__main__":
    unittest.main(verbosity=1)
