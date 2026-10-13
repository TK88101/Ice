"""Unit tests of lab-tool.py (plan 2026-10-07-icebar-preference-hiding, S4
design): every scenario's oracle on synthetic reports -- a passing run, a
failing one per clause that matters, a setup that is not established -- and the
report's damage rules. Run by test-lab.sh: python3 -I test_lab_tool.py.
Side effects: a temporary directory, removed."""
import importlib.util
import json
import os
import shutil
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("labtool", os.path.join(HERE, "lab-tool.py"))
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)

T = "com.icespike4.target"


def member(identifier, condition="ready", frame=(900, 4, 14, 22)):
    return {"namespace": T, "identifier": identifier, "pid": 41, "condition": condition, "pressable": True, "frame": list(frame)}


def cells(names, disabled=False):
    return [{"namespace": T, "identifier": n, "disabled": disabled} for n in names]


def checks(names, outcome="hidden"):
    return [{"namespace": T, "identifier": n, "outcome": outcome} for n in names]


def snapshot(**fields):
    base = {
        "phase": "quiet", "status": "notVerified(lengthNotApplied)", "lengthSet": False, "lengthApplied": False,
        "calibratedHiddenLength": None, "isIceBarOffered": False, "isIceBarPresented": False, "isInteracting": False,
        "roster": [], "blockers": [], "cells": [], "cacheVisible": [], "cacheHidden": [], "cacheAlwaysHidden": [],
        "iconPlacement": None, "hiddenBoundaryUsable": True,
        "icon": {"frame": [1500, 0, 28, 30], "usable": True}, "hiddenDivider": {"frame": [880, 0, 18, 30], "usable": True},
        "alwaysHiddenDivider": None, "completeness": "complete", "pass": 1, "checks": [], "chevronListed": None,
    }
    base.update(fields)
    return base


class Report:
    """Events in order; each line's `seq` is its position."""

    def __init__(self, hold=False):
        self.lines = [{"event": "start", "marker": lab.MARKER, "pid": 7, "bundleID": "com.icespike4.lab.r1", "holdLength": hold}]

    def add(self, event, fields=None):
        line = {"event": event}
        line.update(fields or {})
        self.lines.append(line)
        return len(self.lines)

    def snap(self, **fields):
        return self.add("snapshot", snapshot(**fields))

    def status(self, text):
        return self.add("status", {"status": text})

    def length(self, applied, held=False, decided=None):
        return self.add("length", {"applied": applied, "held": held, "decided": decided if decided is not None else applied})

    def roster(self, *names):
        return self.add("roster", {"members": [{"namespace": T, "identifier": n} for n in names]})

    def rest(self, names, status="verified", **fields):
        values = dict(phase="resting", status=status, lengthSet=True, lengthApplied=True, calibratedHiddenLength=736,
                      isIceBarOffered=True, roster=[member(n) for n in names], cells=cells(names), checks=checks(names))
        values.update(fields)
        return self.snap(**values)

    def text(self):
        out = []
        for index, line in enumerate(self.lines, start=1):
            body = dict(line)
            body["seq"] = index
            body["t"] = index * 0.5
            out.append(json.dumps(body, sort_keys=True))
        return "\n".join(out) + "\n"

    def standard(self, names, cells_disabled=False, check="hidden"):
        """A standard hide: the roster at standard length, a length, verified."""
        self.snap(roster=[member(n) for n in names], cacheHidden=[{"namespace": T, "identifier": n} for n in names])
        self.roster(*names)
        self.length(736)
        self.status("verified")
        return self.rest(names, cells=cells(names, cells_disabled), checks=checks(names, check))


class LabToolTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="labtool")

    def tearDown(self):
        shutil.rmtree(self.root)

    def run_dir(self, scenario, reports, steps=(), **expected):
        directory = os.path.join(self.root, f"1-{scenario}")
        shutil.rmtree(directory, ignore_errors=True)
        os.makedirs(directory)
        for number, report in enumerate(reports, start=1):
            with open(os.path.join(directory, f"report-{number}.jsonl"), "w") as handle:
                handle.write(report if isinstance(report, str) else report.text())
        with open(os.path.join(directory, "steps.jsonl"), "w") as handle:
            for entry in steps:
                handle.write(json.dumps(entry) + "\n")
        body = {"scenario": scenario, "members": [], "blockers": []}
        body.update(expected)
        with open(os.path.join(directory, "expected.json"), "w") as handle:
            json.dump(body, handle)
        return directory

    def judge(self, *args, **kwargs):
        return lab.judge(self.run_dir(*args, **kwargs)).json()

    def result(self, *args, **kwargs):
        return self.judge(*args, **kwargs)["result"]

    def write(self, text):
        path = os.path.join(self.root, "r.jsonl")
        with open(path, "w") as handle:
            handle.write(text)
        return path

    # --- the report itself -------------------------------------------------------

    def test_damaged_reports_are_aborted_never_a_pass(self):
        good = Report()
        good.standard(["a"])
        text = good.text()
        lines = text.splitlines()
        renumbered = [json.dumps(dict(json.loads(line), seq=index)) for index, line in enumerate(lines[1:], start=1)]
        cases = {
            "unfinished": text + '{"event":"status"',
            "not json": text + "nope\n",
            "gap": "\n".join(lines[:2] + lines[3:]) + "\n",
            "no start": "\n".join(renumbered) + "\n",
            "empty": "",
        }
        for name, body in cases.items():
            with self.subTest(name):
                self.assertEqual(self.result("sparse", [body], members=["a"]), "aborted")

    def test_a_snapshot_with_other_keys_is_damage(self):
        report = Report()
        report.add("snapshot", {"phase": "quiet"})
        with self.assertRaises(lab.Damaged):
            lab.load_report(self.write(report.text()))

    def test_while_ice_runs_an_unfinished_last_line_is_left_for_later(self):
        report = Report()
        report.status("verified")
        events = lab.load_report(self.write(report.text() + '{"event":"sta'), final=False)
        self.assertEqual(len(events), 2)

    def test_await_predicates(self):
        report = Report()
        report.snap(roster=[member("a", "stacked")])
        path = self.write(report.text())
        events = lab.load_report(path, final=False)
        self.assertTrue(lab.predicate_holds(events, "stacked", []))
        self.assertFalse(lab.predicate_holds(events, "rest", []))
        self.assertFalse(lab.predicate_holds(events, "verified", ["0"]))
        report.length(736)
        report.status("verified")
        events = lab.load_report(self.write(report.text()), final=False)
        self.assertTrue(lab.predicate_holds(events, "verified", ["0"]))
        self.assertFalse(lab.predicate_holds(events, "verified", [str(len(report.lines))]))
        self.assertTrue(lab.predicate_holds(events, "any-length", ["0"]))

    def test_selfread_frames(self):
        line = 'selfread {"children":[{"identifier":"p","frame":[900,4,14,22]},{"identifier":"q","frame":[1,2,3,4]},{"identifier":"p","frame":[930,4,14,22]}]}'
        self.assertEqual(lab.selfread_frames(line, "p"), [[900, 4, 14, 22], [930, 4, 14, 22]])
        self.assertEqual(lab.selfread_frames("selfread nope", "p"), [])
        self.assertEqual(lab.selfread_frames('frames {"items":[]}', "p"), [])

    def test_wait_reads_a_growing_report_in_one_process(self):
        path = os.path.join(self.root, "grow.jsonl")
        report = Report()
        report.snap()
        with open(path, "w") as handle:
            handle.write(report.text())
        ticks = []

        def sleep(_):
            ticks.append(1)
            if len(ticks) == 2:
                report.status("verified")
                with open(path, "w") as handle:
                    handle.write(report.text() + '{"event":"sta')

        clock = iter(range(100)).__next__
        self.assertEqual(lab.wait(path, 50, 1, "verified", ["0"], clock=clock, sleep=sleep, alive=lambda pid: True), 0)
        self.assertEqual(lab.wait(path, 3, 1, "rest", [], clock=iter(range(100)).__next__, sleep=lambda _: None, alive=lambda pid: True), 1)
        self.assertEqual(lab.wait(path, 3, 1, "rest", [], clock=iter(range(100)).__next__, sleep=lambda _: None, alive=lambda pid: False), 4)
        with open(path, "a") as handle:
            handle.write("\nnope\n")
        self.assertEqual(lab.wait(path, 3, 1, "rest", [], clock=iter(range(100)).__next__, sleep=lambda _: None, alive=lambda pid: True), 3)

    def test_a_run_that_ends_in_another_kind_fails(self):
        report = Report()
        report.standard(["a"])
        report.status("failed(drawn:1)")
        verdict = self.judge("sparse", [report], members=["a"])
        self.assertEqual((verdict["result"], verdict["kind"]), ("fail", "failed"))
        self.assertIn("ended failed, expected verified", verdict["reasons"])

    def test_bracket_key_follows_frames_and_conditions(self):
        one, two = Report(), Report()
        one.snap(roster=[member("a", "stacked")])
        two.snap(roster=[member("a", "stacked", frame=(901, 4, 14, 22))])
        key = lambda report: lab.bracket_key(lab.load_report(self.write(report.text()), final=False), ["a"])
        self.assertNotEqual(key(one), key(two))
        self.assertEqual(key(one), key(one))
        # Only a snapshot that is itself the witness has a key.
        one.snap(roster=[member("a")])
        self.assertEqual(key(one), "")

    # --- sparse and k ------------------------------------------------------------

    def test_sparse_passes(self):
        report = Report()
        report.standard(["a"])
        self.assertEqual(self.result("sparse", [report], members=["a"]), "pass")

    def test_sparse_fails_on_each_clause(self):
        for name, options in {"a cell disabled": dict(cells_disabled=True), "a check not hidden": dict(check="hiddenFolded")}.items():
            with self.subTest(name):
                report = Report()
                report.standard(["a"], **options)
                self.assertEqual(self.result("sparse", [report], members=["a"]), "fail")
        report = Report()
        report.snap(roster=[member("a")])
        report.length(736)
        report.status("notVerified(noReference)")
        self.assertEqual(self.result("sparse", [report], members=["a"]), "fail")

    def test_a_held_length_never_passes_a_scenario_that_applies(self):
        report = Report(hold=True)
        report.standard(["a"])
        self.assertEqual(self.result("sparse", [report], members=["a"]), "fail")

    def test_sparse_setup_not_established(self):
        foreign = dict(member("x"), namespace="com.apple.foo")
        for name, roster in {"a foreign member": [member("a"), foreign], "a missing member": []}.items():
            with self.subTest(name):
                report = Report()
                report.snap(roster=roster)
                report.length(736)
                report.status("verified")
                self.assertEqual(self.result("sparse", [report], members=["a"]), "notEstablished")
        report = Report()
        report.standard(["a"])
        self.assertEqual(self.result("sparse", [report], steps=[{"step": "chevronAtStart", "listed": True}], members=["a"]), "notEstablished")
        report = Report()
        report.snap(roster=[member("a")], iconPlacement="iconLeftOfDivider")
        report.length(736)
        report.status("verified")
        self.assertEqual(self.result("sparse", [report], members=["a"]), "notEstablished")

    # --- press ---------------------------------------------------------------------

    def press_report(self, answer="sent", presented=True):
        report = Report()
        report.standard(["a", "b"])
        report.add("bar", {"action": "open", "answer": "sent"})
        report.rest(["a", "b"], isIceBarPresented=presented)
        for name in "ab":
            report.add("press", {"namespace": T, "identifier": name, "answer": answer})
        return report

    def test_press_passes_and_fails(self):
        steps = [{"step": "menuOpen", "member": m, "seen": True} for m in "ab"]
        self.assertEqual(self.result("press", [self.press_report()], steps=steps, members=["a", "b"]), "pass")
        self.assertEqual(self.result("press", [self.press_report(answer="refused:disabled")], steps=steps, members=["a", "b"]), "fail")
        self.assertEqual(self.result("press", [self.press_report()], steps=steps[:1], members=["a", "b"]), "fail")
        self.assertEqual(self.result("press", [self.press_report(presented=False)], steps=steps, members=["a", "b"]), "fail")

    # --- addremove -------------------------------------------------------------------

    def addremove(self, retire_first_on_add=True, roster_first_on_remove=True):
        report = Report()
        report.standard(["a", "b"])
        added = report.add("noop")
        if retire_first_on_add:
            report.length(None)
            report.roster("a", "b", "c")
        else:
            report.roster("a", "b", "c")
            report.length(None)
        report.standard(["a", "b", "c"])
        removed = report.add("noop")
        if roster_first_on_remove:
            report.roster("a", "c")
            report.length(None)
        else:
            report.length(None)
            report.roster("a", "c")
        report.standard(["a", "c"])
        return report, [{"step": "added", "seq": added}, {"step": "removed", "seq": removed}]

    def test_addremove_order_per_direction(self):
        expected = dict(members=["a", "b"], added="c")
        report, steps = self.addremove()
        self.assertEqual(self.result("addremove", [report], steps=steps, **expected), "pass")
        report, steps = self.addremove(retire_first_on_add=False)
        self.assertEqual(self.result("addremove", [report], steps=steps, **expected), "fail")
        report, steps = self.addremove(roster_first_on_remove=False)
        self.assertEqual(self.result("addremove", [report], steps=steps, **expected), "fail")

    def test_addremove_that_stopped_early_fails_without_crashing(self):
        report = Report()
        report.standard(["a", "b"])
        self.assertEqual(self.result("addremove", [report], members=["a", "b"]), "fail")
        self.assertEqual(self.result("addremove", [Report()], members=[]), "notEstablished")

    # --- noref -------------------------------------------------------------------------

    def test_noref(self):
        report = Report()
        report.snap(roster=[member("a")])
        report.length(736)
        report.status("notVerified(noReference,unchecked:1)")
        report.rest(["a"], status="notVerified(noReference,unchecked:1)")
        self.assertEqual(self.result("noref", [report], members=["a"]), "pass")
        report = Report()
        report.standard(["a"])
        self.assertEqual(self.result("noref", [report], members=["a"]), "fail")

    def test_noref_with_the_systems_own_references_is_not_established(self):
        # Run 20261011-004911: Apple's items were references, so Ice verified.
        report = Report()
        report.add("observation", {"length": 736, "references": [{"namespace": "com.apple.x", "identifier": "", "match": "unique"}]})
        report.standard(["a"])
        verdict = self.judge("noref", [report], members=["a"])
        self.assertEqual((verdict["result"], verdict["reasons"]), ("notEstablished", ["setup: " + lab.EXCLUSIONS["noref"]]))
        # Not with a setup that did not hold: the exclusion must not cover a broken run (Codex review).
        self.assertNotEqual(self.judge("noref", [report], members=["a", "b"])["reasons"], verdict["reasons"])
        report = Report()
        report.add("observation", {"length": 736, "references": [{"namespace": "com.apple.x", "identifier": "", "match": "absent"}]})
        report.standard(["a"])
        self.assertEqual(self.result("noref", [report], members=["a"]), "fail")

    # --- crowded -------------------------------------------------------------------------

    def crowded(self, witness_ok=True, listed_later=True, stacked_status=True, length_at_witness=False):
        report = Report()
        stacked = [member("a", "stacked"), member("b")]
        report.snap(roster=stacked)
        witness = report.add("noop")
        length = report.length(736)
        if length_at_witness:  # the length is the report's last line when the runner marks the witness
            witness = length
        text = "notVerified(stacked:1)" if stacked_status else "verified"
        report.status(text)
        report.rest(["a", "b"], status=text, roster=stacked)
        later = report.add("noop")
        return report, [{"step": "witness", "ok": witness_ok, "seq": witness, "why": "the ladder ended"},
                        {"step": "chevronAtRest", "listed": listed_later, "seq": later}]

    def test_crowded_two_clauses(self):
        expected = dict(members=["a", "b"])
        report, steps = self.crowded()
        verdict = self.judge("crowded", [report], steps=steps, **expected)
        self.assertEqual((verdict["result"], verdict["clauses"]), ("pass", {"12": "pass", "6": "pass"}))
        report, steps = self.crowded(listed_later=False)
        verdict = self.judge("crowded", [report], steps=steps, **expected)
        self.assertEqual((verdict["result"], verdict["clauses"]["6"]), ("fail", "fail"))
        report, steps = self.crowded(stacked_status=False)
        self.assertEqual(self.judge("crowded", [report], steps=steps, **expected)["clauses"]["12"], "fail")
        report, steps = self.crowded(witness_ok=False)
        self.assertEqual(self.result("crowded", [report], steps=steps, **expected), "notEstablished")
        report, steps = self.crowded(length_at_witness=True)
        verdict = self.judge("crowded", [report], steps=steps, **expected)
        self.assertEqual((verdict["result"], verdict["reasons"][0]), ("notEstablished", "setup: a length came before the bracketed witness"))

    def test_crowded_with_the_members_folded_by_the_system_is_not_established(self):
        # Run 20261011-004911: at 21 menus the system folded both members; no roster, no length.
        report = Report()
        report.snap(roster=[member("a"), member("b")])
        witness = report.add("noop")
        report.snap(roster=[])
        steps = [{"step": "witness", "ok": True, "seq": witness}]
        verdict = self.judge("crowded", [report], steps=steps, members=["a", "b"])
        self.assertEqual((verdict["result"], verdict["reasons"]), ("notEstablished", ["setup: " + lab.EXCLUSIONS["crowded"]]))
        report.snap(roster=[member("a"), member("b")])
        self.assertEqual(self.result("crowded", [report], steps=steps, members=["a", "b"]), "fail")
        report.snap(roster=[])
        # Both members were Ice's before the fold, or it is not the measured case (Codex review).
        self.assertEqual(self.result("crowded", [report], steps=steps, members=["a", "b", "c"]), "fail")
        steps = [{"step": "witness", "ok": False, "seq": witness, "why": "the ladder ended"}]
        verdict = self.judge("crowded", [report], steps=steps, members=["a", "b"])
        self.assertNotEqual(verdict["reasons"], ["setup: " + lab.EXCLUSIONS["crowded"]])

    def folded(self, conditions=("ready", "ready"), empties=2, length=False):
        """Run 20261013-000729: both members ready, the ladder starts, then the roster empties."""
        report = Report()
        report.snap(roster=[member("a"), member("b")])
        since = report.add("noop")
        report.snap(roster=[member("a", conditions[0]), member("b", conditions[1])])
        if length:
            report.length(736)
        for _ in range(empties):
            report.snap(roster=[])
        return report, since

    def fold(self, report, since, members=("a", "b")):
        events = lab.parse_lines(report.text().encode().split(b"\n")[:-1], first_seq=1)
        return lab.fold_evidence(events, list(members), since)

    def test_fold_evidence_needs_both_members_ready_then_a_settled_empty_roster(self):
        report, since = self.folded()
        self.assertEqual(self.fold(report, since), {"baseline": 4, "empty": [5, 6]})
        report, since = self.folded(empties=1)
        self.assertIsNone(self.fold(report, since))  # one empty reading may be a missed one (thecure, 2026-10-13)
        report, since = self.folded(conditions=("ready", "stacked"))
        self.assertIsNone(self.fold(report, since))
        report, since = self.folded(length=True)
        self.assertIsNone(self.fold(report, since))
        report, since = self.folded()
        self.assertIsNone(self.fold(report, since, members=("a", "b", "c")))
        self.assertIsNone(self.fold(report, 5))  # an empty roster from before the ladder is not its fold

    def test_crowded_with_a_fold_witness_is_the_measured_exclusion(self):
        report, since = self.folded()
        steps = [{"step": "witness", "ok": True, "folded": True, "since": since, "seq": len(report.lines)}]
        verdict = self.judge("crowded", [report], steps=steps, members=["a", "b"])
        self.assertEqual((verdict["result"], verdict["reasons"]), ("notEstablished", ["setup: " + lab.EXCLUSIONS["crowded"]]))
        # The judge reads the fold itself; the runner's word is not enough.
        report, since = self.folded(empties=1)
        steps = [{"step": "witness", "ok": True, "folded": True, "since": since, "seq": len(report.lines)}]
        verdict = self.judge("crowded", [report], steps=steps, members=["a", "b"])
        self.assertNotEqual(verdict["reasons"], ["setup: " + lab.EXCLUSIONS["crowded"]])

    # --- crowded: the capture indicator's push (run 20261014-003331) -----------------------------

    def divider(self, x):
        return {"frame": [x, 0, 18, 30], "usable": True}

    def pushed(self, x=832, condition="stacked"):
        """Both members ready at the divider's place, then a reading with the divider at `x`."""
        report = Report()
        report.snap(roster=[member("a"), member("b")])
        report.snap(roster=[member("a", condition), member("b", condition)], hiddenDivider=self.divider(x))
        return report

    def is_pushed(self, report, members="a,b"):
        return not lab.predicate_holds(lab.load_report(self.write(report.text()), final=False), "unpushed", [members])

    def test_pushed_is_the_divider_left_of_where_it_stood_with_both_members_ready(self):
        self.assertTrue(self.is_pushed(self.pushed()))
        self.assertFalse(self.is_pushed(self.pushed(x=880)))
        self.assertFalse(self.is_pushed(self.pushed(x=924)))  # the system's fold moves it right
        self.assertFalse(self.is_pushed(self.pushed(), members="a,b,c"))  # never both ready: no place to compare with
        report = self.pushed()
        report.snap(roster=[member("a"), member("b")])
        self.assertFalse(self.is_pushed(report))  # the latest reading counts
        report = self.pushed()
        report.snap(roster=[], hiddenDivider=None)
        self.assertFalse(self.is_pushed(report))
        report = self.pushed()
        report.snap(roster=[member("a"), member("b")], hiddenDivider=self.divider(832), lengthSet=True)
        self.assertFalse(self.is_pushed(report))  # a divider with a length is Ice's own move

    def test_no_witness_is_read_under_the_push(self):
        key = lambda report: lab.bracket_key(lab.load_report(self.write(report.text()), final=False), ["a", "b"])
        self.assertEqual(key(self.pushed()), "")
        self.assertNotEqual(key(self.pushed(x=880)), "")
        report, since = self.folded()
        self.assertIsNotNone(self.fold(report, since))
        report.snap(roster=[], hiddenDivider=self.divider(832))
        self.assertIsNone(self.fold(report, since))

    def test_crowded_with_a_witness_read_under_the_push_is_not_established(self):
        # Run 20261014-003331: at 19 menus the indicator piled both members for 10 s; the witness
        # was read then, the members came back, Ice applied a length and « was not listed.
        report = self.pushed()
        witness = report.add("noop")
        report.snap(roster=[member("a"), member("b")])
        report.length(736)
        report.status("notVerified(noReference,unchecked:2)")
        report.rest(["a", "b"], status="notVerified(noReference,unchecked:2)", chevronListed=False)
        later = report.add("noop")
        steps = [{"step": "witness", "ok": True, "seq": witness}, {"step": "chevronAtRest", "listed": False, "seq": later}]
        verdict = self.judge("crowded", [report], steps=steps, members=["a", "b"])
        self.assertEqual((verdict["result"], verdict["reasons"][0]), ("notEstablished", "setup: " + lab.PUSHED_WITNESS))
        # The same run with the witness read after the push left is judged on its clauses.
        steps[0]["seq"] = witness + 1
        self.assertEqual(self.result("crowded", [report], steps=steps, members=["a", "b"]), "fail")

    def test_crowded_with_a_fold_witness_read_under_the_push_is_not_the_exclusion(self):
        report, since = self.folded()
        report.snap(roster=[], hiddenDivider=self.divider(832))
        steps = [{"step": "witness", "ok": True, "folded": True, "since": since, "seq": len(report.lines)}]
        verdict = self.judge("crowded", [report], steps=steps, members=["a", "b"])
        self.assertEqual((verdict["result"], verdict["reasons"][0]), ("notEstablished", "setup: " + lab.PUSHED_WITNESS))

    # --- fresh, placed, t2d ------------------------------------------------------------------

    def fresh(self, always_left=True, cache_matches=True):
        report = Report()
        always = {"frame": [860 if always_left else 880, 0, 18, 30], "usable": True}
        cached = [{"namespace": T, "identifier": "a"}] + ([{"namespace": T, "identifier": "b"}] if cache_matches else [])
        report.snap(roster=[member("a"), member("b")], alwaysHiddenDivider=always, cacheHidden=cached)
        report.length(736)
        report.status("verified")
        report.rest(["a", "b"])
        return report

    def test_fresh_and_the_t2d_clause(self):
        expected = dict(members=["a", "b"])
        self.assertEqual(self.result("fresh-off", [self.fresh()], **expected), "pass")
        self.assertEqual(self.result("fresh-off", [self.fresh(cache_matches=False)], **expected), "fail")
        verdict = self.judge("fresh-on", [self.fresh(always_left=False)], **expected)
        self.assertEqual((verdict["result"], verdict["clauses"]), ("fail", {"t2d": "fail"}))
        verdict = self.judge("fresh-on", [self.fresh()], **expected)
        self.assertEqual((verdict["result"], verdict["clauses"]), ("pass", {"t2d": "pass"}))

    def test_placed_judges_the_second_start(self):
        expected = dict(members=["a", "b"])
        self.assertEqual(self.result("placed-off", [self.fresh(cache_matches=False), self.fresh()], **expected), "pass")
        self.assertEqual(self.result("placed-off", [self.fresh()], **expected), "fail")

    # --- front -------------------------------------------------------------------------------

    def front(self, length_moves=False, reverify=True):
        report = Report()
        report.standard(["a"])
        steps = []
        for name in ("front", "back"):
            steps.append({"step": name, "ok": True, "seq": report.add("noop")})
            report.status("notVerified(layoutChanged:frontmostAppChanged)")
            if length_moves:
                report.length(None)
            if reverify:
                report.status("verified")
        return report, steps

    def test_front_short_and_long(self):
        report, steps = self.front()
        self.assertEqual(self.result("front-short", [report], steps=steps, members=["a"]), "pass")
        report, steps = self.front(length_moves=True)
        self.assertEqual(self.result("front-short", [report], steps=steps, members=["a"]), "fail")
        report, steps = self.front(reverify=False)
        self.assertEqual(self.result("front-short", [report], steps=steps, members=["a"]), "fail")
        verdict = self.judge("front-long", [report], steps=steps, members=["a"])
        self.assertEqual((verdict["result"], verdict["kind"]), ("pass", "unverified"))
        report, steps = self.front()
        steps[0]["ok"] = False
        self.assertEqual(self.result("front-short", [report], steps=steps, members=["a"]), "notEstablished")

    # --- relaunch ------------------------------------------------------------------------------

    def test_relaunch(self):
        first, second, other = Report(), Report(), Report()
        first.standard(["a", "b"])
        second.standard(["a", "b"])
        other.standard(["a"])
        self.assertEqual(self.result("relaunch", [first, second], members=["a", "b"]), "pass")
        self.assertEqual(self.result("relaunch", [first, other], members=["a", "b"]), "fail")
        self.assertEqual(self.result("relaunch", [first], members=["a", "b"]), "fail")

    # --- the blocked ones --------------------------------------------------------------------------

    def positional(self, length=False, offered=False, bar="refused:notOffered"):
        report = Report()
        report.snap(blockers=[{"namespace": T, "identifier": "p"}] * 2, status="blocked(positional:2)", phase="blocked", isIceBarOffered=offered)
        report.status("blocked(positional:2)")
        if length:
            report.length(736)
        report.add("bar", {"action": "open", "answer": bar})
        return report

    def test_positional(self):
        frames = [[900, 4, 14, 22], [930, 4, 14, 22]]
        steps = [{"step": "frames", "when": "before", "frames": frames}, {"step": "frames", "when": "after", "frames": frames}]
        expected = dict(members=[], blockers=["p", "p"])
        self.assertEqual(self.result("positional", [self.positional()], steps=steps, **expected), "pass")
        for name, report in {"a length": self.positional(length=True), "offered": self.positional(offered=True),
                             "bar opened": self.positional(bar="sent")}.items():
            with self.subTest(name):
                self.assertEqual(self.result("positional", [report], steps=steps, **expected), "fail")
        moved = [steps[0], {"step": "frames", "when": "after", "frames": [[905, 4, 14, 22], [930, 4, 14, 22]]}]
        self.assertEqual(self.result("positional", [self.positional()], steps=moved, **expected), "fail")
        self.assertEqual(self.result("positional", [self.positional()], steps=steps, members=[], blockers=["p"]), "notEstablished")

    def test_inverted_is_not_run(self):
        # The seeding did not invert in two runs; the owner's Command-drag is S5's.
        verdict = self.judge("inverted", [Report()])
        self.assertEqual(verdict["result"], "notRun")
        self.assertIn("seeding", verdict["reasons"][0])

    def test_drawn(self):
        report = Report(hold=True)
        report.snap(roster=[member("a")])
        report.length(None, held=True, decided=736)
        report.status("failed(drawn:1)")
        self.assertEqual(self.result("drawn", [report], members=["a"]), "pass")
        report = Report(hold=True)
        report.status("verified")
        report.status("failed(drawn:1)")
        self.assertEqual(self.result("drawn", [report], members=["a"]), "fail")
        report = Report()
        report.status("failed(drawn:1)")
        self.assertEqual(self.result("drawn", [report], members=["a"]), "notEstablished")

    def test_incomplete(self):
        def make(retire=True, recover=True):
            """As the runner marks: a step's `seq` is the report's last line then."""
            report = Report()
            stall = report.standard(["a"])
            if retire:
                report.length(None)
            resumed = report.status("blocked(discoveryIncomplete)")
            settled = report.status("notVerified(lengthNotApplied)") if recover else resumed
            return report, [{"step": "stall", "seq": stall}, {"step": "resumed", "seq": resumed}, {"step": "settled", "seq": settled}]
        for options, wanted in (({}, "pass"), ({"retire": False}, "fail"), ({"recover": False}, "fail")):
            with self.subTest(options):
                report, steps = make(**options)
                self.assertEqual(self.result("incomplete", [report], steps=steps, members=["a"]), wanted)

    def test_incomplete_needs_a_rest_at_the_stall(self):
        report = Report()
        report.snap(roster=[member("a")])
        stall = report.length(736)  # a length set, no rest yet
        resumed = report.status("blocked(discoveryIncomplete)")
        settled = report.status("notVerified(lengthNotApplied)")
        steps = [{"step": "stall", "seq": stall}, {"step": "resumed", "seq": resumed}, {"step": "settled", "seq": settled}]
        self.assertEqual(self.result("incomplete", [report], steps=steps, members=["a"]), "notEstablished")
        steps[0]["seq"] = 0  # marked before the report held a line
        self.assertEqual(self.result("incomplete", [report], steps=steps, members=["a"]), "notEstablished")

    def test_a_snapshot_at_a_steps_seq_is_before_the_step(self):
        report = Report()
        first = report.snap(phase="settling")
        report.status("notVerified(unchecked:1)")
        second = report.rest(["a"])
        events = lab.load_report(self.write(report.text()))
        self.assertEqual(lab.snapshot_at_or_before(events, second)["phase"], "resting")
        self.assertEqual(lab.snapshot_at_or_before(events, second - 1)["phase"], "settling")
        self.assertEqual(lab.snapshot_at_or_before(events, first)["phase"], "settling")
        self.assertIsNone(lab.snapshot_at_or_before(events, first - 1))
        self.assertIsNone(lab.snapshot_at_or_before(events, 0))

    def test_the_chevron_at_start_clause_applies_to_every_checked_scenario(self):
        listed = [{"step": "chevronAtStart", "listed": True}]
        report = Report()
        report.standard(["a"])
        for scenario in ("sparse", "incomplete", "drawn", "noref"):
            with self.subTest(scenario):
                self.assertEqual(self.result(scenario, [report], steps=listed, members=["a"]), "notEstablished")
        crowded, steps = self.crowded()
        self.assertEqual(self.result("crowded", [crowded], steps=steps + listed, members=["a", "b"]), "pass")

    def test_inverted_moved_is_not_run(self):
        self.assertEqual(self.result("inverted-moved", [Report()]), "notRun")

    def test_a_runner_abort_wins(self):
        report = Report()
        report.standard(["a"])
        self.assertEqual(self.result("sparse", [report], steps=[{"step": "aborted", "why": "Ice did not start"}], members=["a"]), "aborted")

    # --- the matrix ----------------------------------------------------------------------------------

    def write_verdict(self, number, scenario, result, clauses=None, reasons=None):
        directory = os.path.join(self.root, f"{number}-{scenario}")
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, "verdict.json"), "w") as handle:
            json.dump({"scenario": scenario, "result": result, "clauses": clauses or {}, "reasons": reasons or [], "kind": None}, handle)

    def full_round(self, number):
        for name in lab.ORDER:
            self.write_verdict(number, name, "notRun" if lab.SCENARIOS[name]["kind"] == "notRun" else "pass")

    def test_a_named_exclusion_with_its_measured_reason_keeps_a_round_clean(self):
        for number in (1, 2, 3):
            self.full_round(number)
            for name, reason in lab.EXCLUSIONS.items():
                self.write_verdict(number, name, "notEstablished", {}, ["setup: " + reason])
        self.assertTrue(lab.round_is_clean(lab.matrix(self.root)[1]))
        self.assertEqual(lab.report(self.root), 0)
        # Near misses: another reason beside it, another scenario with it, another result.
        self.write_verdict(1, "noref", "notEstablished", {}, ["setup: " + lab.EXCLUSIONS["noref"], "no length was applied"])
        self.assertFalse(lab.round_is_clean(lab.matrix(self.root)[1]))
        self.assertEqual(lab.report(self.root), 1)
        self.write_verdict(1, "noref", "notEstablished", {}, ["setup: " + lab.EXCLUSIONS["noref"]])
        self.write_verdict(1, "sparse", "notEstablished", {}, ["setup: " + lab.EXCLUSIONS["noref"]])
        self.assertFalse(lab.round_is_clean(lab.matrix(self.root)[1]))
        self.write_verdict(1, "sparse", "pass")
        self.write_verdict(1, "crowded", "fail", {}, ["setup: " + lab.EXCLUSIONS["crowded"]])
        self.assertFalse(lab.round_is_clean(lab.matrix(self.root)[1]))
        self.assertEqual(lab.report(self.root), 1)

    def test_round_clean_ignores_only_known_open_clauses(self):
        self.full_round(1)
        self.write_verdict(1, "fresh-on", "fail", {"t2d": "fail"}, ["t2d: the always-hidden divider is not left of the hidden one"])
        self.assertTrue(lab.round_is_clean(lab.matrix(self.root)[1]))
        self.write_verdict(1, "fresh-on", "fail", {"t2d": "fail"}, ["t2d: x", "never verified"])
        self.assertFalse(lab.round_is_clean(lab.matrix(self.root)[1]))
        self.write_verdict(1, "fresh-on", "pass")
        self.write_verdict(1, "sparse", "notEstablished", {}, ["setup: x"])
        self.assertFalse(lab.round_is_clean(lab.matrix(self.root)[1]))

    def test_dod_needs_three_clean_rounds(self):
        for number in (1, 2, 3):
            self.full_round(number)
        self.assertEqual(lab.report(self.root), 0)
        self.write_verdict(3, "fresh-on", "fail", {"t2d": "fail"}, ["t2d: x"])
        self.assertEqual(lab.report(self.root), 1)
        shutil.rmtree(os.path.join(self.root, "3-sparse"))
        self.write_verdict(3, "fresh-on", "pass")
        self.assertEqual(lab.report(self.root), 1)


if __name__ == "__main__":
    unittest.main(verbosity=1)
