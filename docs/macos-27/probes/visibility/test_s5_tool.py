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
        # 0.5 s a line: two snapshots of a rest in a row make a lasting one
        self.mark("iceStarted", **dict({"rest": 0.5}, **bend.get("iceStarted", {})))
        r.snap(hiddenBoundaryUsable=False, cacheVisible=BAR + [ICE_ITEM])
        r.snap(cacheVisible=bend.get("startVisible", BAR) + [ICE_ITEM], cacheHidden=bend.get("startHidden", []),
               iconPlacement=bend.get("startPlacement"), roster=bend.get("startRoster", []))
        self.mark("helperUp", id=HELPER, **bend.get("helperUp", {}))
        held = bend.get("helperRoster", [helper])
        r.snap(roster=held, cacheHidden=entries(helper), cacheVisible=BAR + [ICE_ITEM])
        r.length(736)
        r.status(bend.get("helperStatus", "verified"))
        for _ in range(1 if bend.get("shortRest") else 2):
            rest(r, held, BAR, status=bend.get("helperStatus", "verified"))
        if bend.get("shortRest"):
            r.snap(roster=held, cacheVisible=BAR + [ICE_ITEM])
        if not bend.get("neverPresented"):
            rest(r, held, BAR, isIceBarPresented=True, status=bend.get("helperStatus", "verified"))
        self.answer("helperGone")
        self.answer("helperListed")
        self.answer("helperMenu")
        self.answer("doOwn", "y" if self.own else "s")
        if self.own:
            both = [helper, own_member(**bend.get("ownMember", {}))]
            r.snap(roster=both, blockers=bend.get("blockers", []), cacheHidden=entries(*both), cacheVisible=without_own + [ICE_ITEM])
            if not bend.get("neverSeen"):
                self.mark("ownSeen", member=dict(OWN))
            if "C5" in bend.get("timedOut", []):
                self.mark("timedOut", clause="C5", wait="verified")
            for text in bend.get("ownBefore", []):
                r.status(text)
            r.status(bend.get("ownStatus", "verified"))
            rest(r, both, without_own, status=bend.get("ownStatus", "verified"))
            rest(r, both, without_own, isIceBarPresented=True, status=bend.get("ownStatus", "verified"),
                 cells=bend.get("ownCells", [dict(e, disabled=False) for e in entries(*both)]))
            self.mark("ownName", name="the example item")
            self.answer("ownListed")
            self.answer("ownMenu")
        self.answer("doInvert", "y" if self.invert else "s")
        if self.invert:
            if not bend.get("neverRetired"):
                r.length(None)
            r.status(bend.get("invertStatus", "blocked(iconLeftOfDivider)"))
            r.snap(status="blocked(iconLeftOfDivider)", iconPlacement="iconLeftOfDivider", isIceBarOffered=bend.get("offeredWhileBlocked", False),
                   calibratedHiddenLength=bend.get("blockedLength"),
                   roster=[helper], cacheVisible=BAR + [ICE_ITEM])
            if "C6" in bend.get("timedOut", []):
                self.mark("timedOut", clause="C6", wait="verified")
            self.answer("paneSays")
            r.length(736)
            if not bend.get("neverBack"):
                r.status("verified")
                rest(r, [helper], BAR)
                rest(r, [helper], BAR)
            self.answer("paneClear")
        if self.own:
            self.answer("itemBack")
        self.mark("lastLook")
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
        # The fixture goes on as a sitting that passed, so its end does not match
        # this start: the clauses are what is judged here (test-s5.sh has the result).
        verdict = self.judge(startHidden=[OWN])
        self.assertEqual(verdict["clauses"]["C1"], "notEstablished", verdict["reasons"])
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

    def test_the_start_is_judged_by_the_limit_the_runner_waited(self):
        # the settled snapshot is the report's third line: 1.5 s
        self.assert_clause(self.judge(iceStarted={"limit": 1}), "C1", "notEstablished", "notEstablished")
        self.assertEqual(self.judge(iceStarted={"limit": 2})["clauses"]["C1"], "pass")

    def test_the_order_is_judged_also_when_the_sitting_ended_at_an_earlier_clause(self):
        verdict = self.judge(helperRoster=[], endVisible=list(reversed(BAR)))
        self.assertEqual(verdict["clauses"]["C2"], "notEstablished")
        self.assert_clause(verdict, "C8", "changed", "fail")

    def test_a_helper_that_never_becomes_the_member_is_not_established(self):
        self.assert_clause(self.judge(helperRoster=[]), "C2", "notEstablished", "notEstablished")

    def test_a_roster_that_is_not_the_helper_alone_is_not_established(self):
        self.assert_clause(self.judge(helperRoster=[member(HELPER), own_member()]), "C2", "notEstablished", "notEstablished")

    def test_a_helper_that_is_not_pressable_is_not_established(self):
        self.assert_clause(self.judge(helperRoster=[member(HELPER, "stacked")]), "C2", "notEstablished", "notEstablished")

    def test_a_helper_that_became_the_member_after_the_runners_wait_is_not_established(self):
        # 0.5 s a line: the roster comes 0.5 s after the helper's start
        self.assert_clause(self.judge(helperUp={"limit": 0.25}), "C2", "notEstablished", "notEstablished")
        self.assertEqual(self.judge(helperUp={"limit": 1})["clauses"]["C2"], "pass")

    # --- C3, C4: the helper hidden and reachable ----------------------------------------

    def test_a_verified_after_the_runner_stopped_waiting_does_not_count(self):
        sitting = Sitting(own=False, invert=False).build()
        sitting.steps = [e for e in sitting.steps if e["step"] in ("helperUp", "stopping", "cleanup")]
        sitting.steps.insert(1, dict(step="timedOut", seq=3, t=1.0, clause="C3", wait="verified"))
        sitting.build = lambda: sitting
        verdict = self.judge(sitting)
        self.assert_clause(verdict, "C3", "fail", "fail")
        self.assertIn("ran out (last status: none)", " ".join(verdict["reasons"]))

    def test_cells_that_are_not_the_roster_fail_the_rest(self):
        reasons = s5.rest_reasons(*self.rest_with(cells=[]), 0)
        self.assertEqual(reasons, ["the IceBar's cells are not the members, each enabled"])

    def test_a_rest_ice_could_not_verify_counts_and_is_noted(self):
        verdict = self.judge(helperStatus="notVerified(noReference,unchecked:1)")
        self.assertEqual(verdict["result"], "pass", verdict["reasons"])
        self.assertFalse(verdict["verified"])
        self.assertIn("the helper: hidden, not verified: Ice said notVerified(noReference,unchecked:1)", verdict["notes"])

    def test_a_verified_rest_is_recorded_as_verified(self):
        self.assertTrue(self.judge()["verified"])

    def test_a_rest_that_did_not_last_fails_and_names_the_status(self):
        sitting = Sitting(own=False, invert=False)
        sitting.bend.update(shortRest=True, neverPresented=True)
        verdict = self.judge(sitting)
        self.assert_clause(verdict, "C3", "fail", "fail")
        self.assertIn("never rested with the length applied for 0.5 s (last status: verified)", " ".join(verdict["reasons"]))

    def test_a_helper_the_owner_still_sees_on_the_bar_fails(self):
        self.assert_clause(self.judge(helperGone="n"), "C3", "fail", "fail")

    def test_a_rest_lasts_only_without_a_break(self):
        report = Report()
        for lasting in (True, False, True):
            rest(report, [member(HELPER)], BAR, phase="resting" if lasting else "quiet")
        path = os.path.join(self.root, "broken.jsonl")
        with open(path, "w") as handle:
            handle.write(report.text())
        events = s5.lab.load_report(path)
        self.assertIsNone(s5.lasting_rest(events, 0, 1.0))
        self.assertIsNotNone(s5.lasting_rest(events, 0, 0.0))

    def test_a_no_to_the_helper_question_fails(self):
        self.assert_clause(self.judge(helperMenu="n"), "C4", "fail", "fail")

    def test_a_yes_without_the_bar_presented_in_the_report_fails(self):
        self.assert_clause(self.judge(neverPresented=True), "C4", "fail", "fail")

    def rest_with(self, **fields):
        report = Report()
        report.status("verified")
        rest(report, [member(HELPER)], BAR, **fields)
        path = os.path.join(self.root, "rest.jsonl")
        with open(path, "w") as handle:
            handle.write(report.text())
        return s5.lab.load_report(path), [{"namespace": T, "identifier": HELPER}], 0, None

    # --- C5: the owner's item -----------------------------------------------------------

    def test_an_own_item_ice_never_saw_fails(self):
        verdict = self.judge(neverSeen=True)
        self.assert_clause(verdict, "C5", "fail", "fail")
        self.assertIn("no second member was seen", " ".join(verdict["reasons"]))

    def test_an_own_item_whose_wait_ran_out_fails_whatever_the_report_shows_later(self):
        verdict = self.judge(timedOut=["C5"])
        self.assert_clause(verdict, "C5", "fail", "fail")
        self.assertIn("C5: the runner's wait for verified ran out", " ".join(verdict["reasons"]))

    def test_an_icebar_shown_only_after_the_owners_answer_does_not_count(self):
        sitting = Sitting(own=False, invert=False)
        sitting.bend["neverPresented"] = True
        sitting.build()
        rest(sitting.report, [member(HELPER)], BAR, isIceBarPresented=True)
        sitting.build = lambda: sitting
        self.assert_clause(self.judge(sitting), "C4", "fail", "fail")

    def test_a_positional_blocker_on_the_way_fails_and_is_named(self):
        verdict = self.judge(ownBefore=["blocked(positional:1)"])
        self.assert_clause(verdict, "C5", "fail", "fail")
        self.assertIn("Ice said blocked(positional:1)", " ".join(verdict["reasons"]))

    def test_a_positional_blocker_after_the_owners_answer_is_not_this_steps(self):
        sitting = Sitting().build()
        sitting.report.status("blocked(positional:1)")
        sitting.build = lambda: sitting
        self.assertEqual(self.judge(sitting)["clauses"]["C5"], "pass")

    def test_a_stale_own_member_fails(self):
        self.assert_clause(self.judge(ownMember={"condition": "stale", "pressable": False}), "C5", "fail", "fail")

    def test_a_disabled_cell_fails(self):
        cells = [dict(e, disabled=True) for e in entries(member(HELPER), own_member())]
        self.assert_clause(self.judge(ownCells=cells), "C5", "fail", "fail")

    def test_an_own_item_ice_could_not_verify_counts_and_is_noted(self):
        verdict = self.judge(ownStatus="notVerified(unchecked:1)")
        self.assertEqual(verdict["clauses"]["C5"], "pass", verdict["reasons"])
        self.assertIn("the owner's item: hidden, not verified: Ice said notVerified(unchecked:1)", verdict["notes"])

    # --- C6: the icon left of the divider ------------------------------------------------

    def test_no_blocked_status_after_the_drag_fails(self):
        self.assert_clause(self.judge(invertStatus="notVerified(lengthNotApplied)"), "C6", "fail", "fail")

    def test_an_icebar_offered_while_blocked_fails(self):
        self.assert_clause(self.judge(offeredWhileBlocked=True), "C6", "fail", "fail")

    def test_a_length_still_standing_while_blocked_fails(self):
        self.assert_clause(self.judge(blockedLength=736), "C6", "fail", "fail")

    def test_a_length_never_retired_fails(self):
        verdict = self.judge(neverRetired=True)
        self.assert_clause(verdict, "C6", "fail", "fail")
        self.assertIn("not retired", " ".join(verdict["reasons"]))

    def test_never_verified_again_after_the_drag_back_fails(self):
        self.assert_clause(self.judge(neverBack=True), "C6", "fail", "fail")

    def test_a_wait_that_ran_out_during_the_icon_drag_fails(self):
        verdict = self.judge(timedOut=["C6"])
        self.assert_clause(verdict, "C6", "fail", "fail")
        self.assertIn("C6: the runner's wait for verified ran out", " ".join(verdict["reasons"]))

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

    def test_an_item_not_put_back_is_changed_and_the_measured_order_is_still_shown(self):
        verdict = self.judge(itemBack="n", endVisible=list(reversed(BAR)))
        self.assert_clause(verdict, "C8", "changed", "fail")
        self.assertEqual(verdict["orderBefore"], BAR)
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
        self.assertTrue(s5.predicate_holds(events, "rested", ["0", "0.5", "1"]))
        self.assertFalse(s5.predicate_holds(events, "rested", ["0", "0.5", "3"]))
        self.assertFalse(s5.predicate_holds(events, "rested", ["0", "60"]))
        self.assertTrue(s5.predicate_holds(events, "verified", ["0"]))
        self.assertTrue(s5.predicate_holds(events, "status", ["0", "blocked(iconLeftOfDivider"]))

    def test_wait_ends_as_held_timed_out_damaged_or_ice_gone(self):
        events, _ = self.events()
        path = os.path.join(self.root, "r.jsonl")
        ticks = iter(range(100))
        kwargs = dict(clock=lambda: next(ticks), sleep=lambda _: None)
        self.assertEqual(s5.wait(path, 5, 1, lambda e: True, alive=lambda _: True, **kwargs), 0)
        self.assertEqual(s5.wait(path, 5, 1, lambda e: False, alive=lambda _: True, **kwargs), 1)
        self.assertEqual(s5.wait(path, 5, 1, lambda e: False, alive=lambda _: False, **kwargs), 4)
        with open(path, "a") as handle:
            handle.write("nope\n")
        self.assertEqual(s5.wait(path, 5, 1, lambda e: True, alive=lambda _: True, **kwargs), 3)

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
