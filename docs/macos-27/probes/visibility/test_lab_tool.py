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
        self.assertTrue(lab.predicate_holds(events, "roster", ["0", "a"]))
        self.assertFalse(lab.predicate_holds(events, "roster", ["0", "a,b"]))
        self.assertFalse(lab.predicate_holds(events, "rest", []))
        self.assertFalse(lab.predicate_holds(events, "verified", ["0"]))
        report.length(736)
        report.status("verified")
        events = lab.load_report(self.write(report.text()), final=False)
        self.assertTrue(lab.predicate_holds(events, "verified", ["0"]))
        self.assertFalse(lab.predicate_holds(events, "verified", [str(len(report.lines))]))
        self.assertTrue(lab.predicate_holds(events, "any-length", ["0"]))

    def test_status_with_and_selfread_frames(self):
        report = Report()
        report.status("notVerified(noReference,unchecked:1)")
        events = lab.load_report(self.write(report.text()), final=False)
        self.assertTrue(lab.predicate_holds(events, "status-with", ["0", "notVerified(", "noReference"]))
        self.assertFalse(lab.predicate_holds(events, "status-with", ["0", "notVerified(", "stacked:"]))
        line = 'selfread {"children":[{"identifier":"p","frame":[900,4,14,22]},{"identifier":"q","frame":[1,2,3,4]},{"identifier":"p","frame":[930,4,14,22]}]}'
        self.assertEqual(lab.selfread_frames(line, "p"), [[900, 4, 14, 22], [930, 4, 14, 22]])
        self.assertEqual(lab.selfread_frames("selfread nope", "p"), [])
        self.assertEqual(lab.selfread_frames('frames {"items":[]}', "p"), [])

    def test_bracket_key_follows_frames_and_conditions(self):
        one, two = Report(), Report()
        one.snap(roster=[member("a", "stacked")])
        two.snap(roster=[member("a", "stacked", frame=(901, 4, 14, 22))])
        key = lambda report: lab.bracket_key(lab.load_report(self.write(report.text()), final=False))
        self.assertNotEqual(key(one), key(two))
        self.assertEqual(key(one), key(one))

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
        first, second = (report.length, report.roster) if retire_first_on_add else (report.roster, report.length)
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

    # --- crowded -------------------------------------------------------------------------

    def crowded(self, witness_ok=True, listed_later=True, stacked_status=True):
        report = Report()
        stacked = [member("a", "stacked"), member("b")]
        report.snap(roster=stacked)
        witness = report.add("noop")
        report.length(736)
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

    def test_inverted(self):
        report = Report()
        report.snap(iconPlacement="iconLeftOfDivider", status="blocked(iconLeftOfDivider)", phase="blocked")
        report.status("blocked(iconLeftOfDivider)")
        self.assertEqual(self.result("inverted", [report], members=["a"]), "pass")
        report = Report()
        report.standard(["a"])
        self.assertEqual(self.result("inverted", [report], members=["a"]), "notEstablished")

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
            report = Report()
            report.standard(["a"])
            stall = report.add("noop")
            if retire:
                report.length(None)
            report.status("blocked(discoveryIncomplete)")
            resumed = report.add("noop")
            if recover:
                report.status("notVerified(lengthNotApplied)")
            settled = report.add("noop")
            return report, [{"step": "stall", "seq": stall}, {"step": "resumed", "seq": resumed}, {"step": "settled", "seq": settled}]
        for options, wanted in (({}, "pass"), ({"retire": False}, "fail"), ({"recover": False}, "fail")):
            with self.subTest(options):
                report, steps = make(**options)
                self.assertEqual(self.result("incomplete", [report], steps=steps, members=["a"]), wanted)

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
            self.write_verdict(number, name, "notRun" if name == "inverted-moved" else "pass")

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
