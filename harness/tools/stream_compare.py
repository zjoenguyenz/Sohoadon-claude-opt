#!/usr/bin/env python3
"""stream_compare — Phase 0 measurement tool (team side, NOT app code).

Compares two runs of the harness `images --dump DIR` stream output
(one `<case>.stream.json` per image), e.g. the GATE100 lane at
`--topk 1` (run A) vs `--topk 3` (run B), case by case.

Per case it reports:
  * parse-outcome class in each run: closed / unclosed / all-nil
      closed   = E1 (sum of items == subtotal) and E2 (subtotal + tax
                 within 2c of total) both hold
      all-nil  = no subtotal, no total and no tax parsed
      unclosed = anything else
  * the winning candidate's subtotal / tax / total (cents) and score
  * whether the class changed and whether the winning totals changed
and ends with a summary count of changed vs unchanged cases.

Input compatibility: dumps with the Phase 0 keys (`dumpSchema`
"phase0-v1": per-candidate `parseSummary` / `scoreComponents`, top-level
`parseSummary`) are read directly; older dumps (only the `parse`
summary string + `e1`/`e2`) are still accepted — values are recovered
from the `parse` string. Both are the winner's FINAL read (ReadOutcome,
after ROI), so the two runs are always compared at the same stage. Score = the winning candidate's app score
(`candidates[winner].score`, i.e. scoreTotal) when recorded, else the
driver's top-level `score`.

Round 3 / Phase 0 additions (tooling only, appended to the report,
default output above them unchanged):
  * READ lines: per case, the FULL final read string of the winner
    (`parse`: vendor, subtotal, tax, total, items, sumItems, sold, card,
    warnings) in both runs and whether ANY of those fields changed —
    "kết quả đọc", not only class + totals.
  * CAND lines: EVERY candidate of every case in both runs — kind,
    transform, gate, winner, score, fragments, lines, the non-zero
    scoreComponents, and a parse summary DERIVED from scoreComponents
    (which equations closed: e1/e2/e3; has subtotal/total/tax line/
    date/vendor). Losing candidates carry no stored ParseResult in the
    app's diagnostics, so their cent values are not available; the
    derived summary is exactly what the app scored.
  * EVIDENCE lines per case: the evidence-richest candidate (most
    evidence flags, tie -> more fragments) vs the winner.

Stdlib only. Usage:
  python3 stream_compare.py RUN_A_DIR RUN_B_DIR
          [--label-a A] [--label-b B] [--focus CASE ...] [--json OUT]
          [--expect N]
Last line of stdout is always "STREAM-COMPARE-DONE" on success.
Exit 0 on success (changes are reported, not failed), 2 on bad input,
3 when --expect N is given and either run does not have N dumps (the
report and STREAM-COMPARE-DONE are still printed).
"""
import argparse
import json
import pathlib
import re
import sys

SUFFIX = ".stream.json"
MISSING_SCORE = -999999
CLASSES = ("closed", "unclosed", "all-nil")
_PARSE_FIELD = re.compile(r"(\w+)=(\S+)")


def _int_or_none(v):
    if v is None or v == "nil":
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _from_parse_string(text):
    """Legacy `parse` string -> subtotal/tax/total/itemCount (cents)."""
    fields = dict(_PARSE_FIELD.findall(text or ""))
    return {
        "subtotalCents": _int_or_none(fields.get("subtotal")),
        "taxCents": _int_or_none(fields.get("tax")),
        "totalCents": _int_or_none(fields.get("total")),
        "itemCount": _int_or_none(fields.get("items")),
    }


def _derive_class(summary, e1, e2):
    if e1 and e2:
        return "closed"
    tax = summary.get("taxCents")
    tax_lines = summary.get("taxLines")
    no_tax = (tax_lines == 0) if tax_lines is not None else not tax
    if (summary.get("subtotalCents") is None
            and summary.get("totalCents") is None and no_tax):
        return "all-nil"
    return "unclosed"


def winner_view(dump):
    """Winning candidate's outcome from one stream dump."""
    candidates = dump.get("candidates") or []
    winners = [c for c in candidates if c.get("winner") in (1, True)]
    win = winners[0] if winners else None

    # Always the FINAL read of the winner (ReadOutcome, after ROI): the
    # top-level parseSummary, or the legacy `parse` string, which is the
    # same stage. Per-candidate parseSummary may be the raw candidate
    # parse (source "candidateRecord"), so it is not mixed in here.
    if (dump.get("parseSummary") or {}).get("available"):
        summary, source = dump["parseSummary"], "parseSummary"
    else:
        summary, source = _from_parse_string(dump.get("parse")), "parse-string"

    e1 = summary.get("e1", dump.get("e1", False))
    e2 = summary.get("e2", dump.get("e2", False))
    cls = summary.get("outcomeClass")
    if cls not in CLASSES:
        cls = _derive_class(summary, e1, e2)

    score = None
    if win is not None and win.get("score") not in (None, MISSING_SCORE):
        score = win.get("score")
    elif dump.get("score") is not None:
        score = dump.get("score")

    return {
        "read": dump.get("parse") or "",
        "cands": [_cand_view(c) for c in candidates],
        "class": cls,
        "subtotalCents": summary.get("subtotalCents"),
        "taxCents": summary.get("taxCents"),
        "totalCents": summary.get("totalCents"),
        "score": score,
        "winnerKind": win.get("kind") if win else None,
        "candidates": len(candidates),
        "source": source,
    }


EVIDENCE_KEYS = ("e1ExactClosure", "e2Within2c", "e3ItemCount", "hasSubtotal",
                 "hasTotal", "hasTaxLine", "hasDate", "vendorResolved")


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def _cand_view(c):
    comps = c.get("scoreComponents") or {}
    flags = {k: _num(comps.get(k)) > 0 for k in EVIDENCE_KEYS}
    return {
        "kind": c.get("kind"), "transform": c.get("transform"),
        "gate": c.get("gate"), "winner": c.get("winner") in (1, True),
        "score": c.get("score"), "fragments": c.get("fragments"),
        "lines": c.get("lines"),
        "components": {k: comps[k] for k in sorted(comps) if _num(comps[k]) != 0},
        "componentsSource": c.get("scoreComponentsSource", "n/a"),
        "flags": flags,
        "evidence": sum(1 for v in flags.values() if v),
    }


def _cand_line(case, label, idx, cv):
    f = cv["flags"]
    derived = (f"e1={'Y' if f['e1ExactClosure'] else 'n'} "
               f"e2={'Y' if f['e2Within2c'] else 'n'} "
               f"e3={'Y' if f['e3ItemCount'] else 'n'} "
               f"sub={'Y' if f['hasSubtotal'] else 'n'} "
               f"tot={'Y' if f['hasTotal'] else 'n'} "
               f"tax={'Y' if f['hasTaxLine'] else 'n'} "
               f"date={'Y' if f['hasDate'] else 'n'} "
               f"vendor={'Y' if f['vendorResolved'] else 'n'}")
    comps = " ".join(f"{k}={_num(v):.3f}" for k, v in cv["components"].items())
    return (f"CAND {case} {label} #{idx} kind={cv['kind']} "
            f"winner={'YES' if cv['winner'] else 'no'} score={_score(cv['score'])} "
            f"gate={cv['gate'] or '-'} frags={cv['fragments']} lines={cv['lines']} "
            f"evidence={cv['evidence']}/8 [{derived}] "
            f"components({cv['componentsSource']}): {comps or '(none)'}")


def render_detail(rows, label_a, label_b):
    out = ["# READ: full final read string of the winner, both runs"]
    read_changed = []
    for r in rows:
        if r["status"] != "both":
            continue
        ra, rb = r["a"]["read"], r["b"]["read"]
        same = ra == rb
        if not same:
            read_changed.append(r["case"])
        out.append(f"READ {r['case']}: {'không đổi' if same else 'ĐỔI'} | "
                   f"{label_a}: {ra} | {label_b}: {rb}")
    out.append(f"READ-SUMMARY changed={len(read_changed)} "
               f"cases={','.join(read_changed) or '-'}")
    out.append("# CAND: every candidate; summary derived from scoreComponents")
    for r in rows:
        for label, key in ((label_a, "a"), (label_b, "b")):
            v = r[key]
            if v is None:
                continue
            for i, cv in enumerate(v["cands"]):
                out.append(_cand_line(r["case"], label, i, cv))
            if v["cands"]:
                rich = max(range(len(v["cands"])),
                           key=lambda i: (v["cands"][i]["evidence"],
                                          v["cands"][i]["fragments"] or 0))
                win = next((i for i, c in enumerate(v["cands"]) if c["winner"]), None)
                out.append(f"EVIDENCE {r['case']} {label} richest=#{rich} "
                           f"({v['cands'][rich]['kind']}, {v['cands'][rich]['evidence']}/8) "
                           f"winner=#{win if win is not None else '-'}"
                           + (f" ({v['cands'][win]['kind']}, {v['cands'][win]['evidence']}/8)"
                              if win is not None else "")
                           + (" SAME" if win == rich else " DIFFERENT"))
    return out


def _die(msg):
    print(f"stream_compare: {msg}", file=sys.stderr)
    raise SystemExit(2)


def load_run(directory):
    d = pathlib.Path(directory)
    if not d.is_dir():
        _die(f"not a directory: {directory}")
    run = {}
    for f in sorted(d.glob("*" + SUFFIX)):
        case = f.name[: -len(SUFFIX)]
        try:
            run[case] = winner_view(json.loads(f.read_text(encoding="utf-8")))
        except (ValueError, AttributeError) as exc:
            _die(f"bad stream JSON {f}: {exc}")
    return run


def compare(run_a, run_b):
    rows = []
    for case in sorted(set(run_a) | set(run_b)):
        a, b = run_a.get(case), run_b.get(case)
        if a is None or b is None:
            rows.append({"case": case, "a": a, "b": b,
                         "status": "only-A" if b is None else "only-B",
                         "classChanged": None, "totalsChanged": None,
                         "changed": True})
            continue
        key = ("subtotalCents", "taxCents", "totalCents")
        class_changed = a["class"] != b["class"]
        totals_changed = any(a[k] != b[k] for k in key)
        rows.append({"case": case, "a": a, "b": b,
                     "status": "both",
                     "classChanged": class_changed,
                     "totalsChanged": totals_changed,
                     "changed": class_changed or totals_changed})
    return rows


def _money(v):
    return "nil" if v is None else str(v)


def _score(v):
    return "nil" if v is None else f"{float(v):.1f}"


def _side(v):
    if v is None:
        return "(missing)"
    return (f"{v['class']:<8} {_money(v['subtotalCents'])}/"
            f"{_money(v['taxCents'])}/{_money(v['totalCents'])} "
            f"score={_score(v['score'])}")


def render(rows, label_a, label_b, focus, coverage=None):
    out = [f"STREAM-COMPARE A={label_a} B={label_b} cases={len(rows)}",
           "# per case: class subtotal/tax/total (cents) score of the "
           "winning candidate"]
    for r in rows:
        if r["status"] != "both":
            flag = r["status"]
        else:
            flag = ("CHANGED" if r["changed"] else "same") + (
                f" class={'yes' if r['classChanged'] else 'no'}"
                f" totals={'yes' if r['totalsChanged'] else 'no'}")
        out.append(f"CASE {r['case']}: {label_a}[{_side(r['a'])}] -> "
                   f"{label_b}[{_side(r['b'])}] {flag}")

    both = [r for r in rows if r["status"] == "both"]
    changed = sum(1 for r in both if r["changed"])
    transitions = {}
    for r in both:
        if r["classChanged"]:
            k = f"{r['a']['class']}->{r['b']['class']}"
            transitions[k] = transitions.get(k, 0) + 1
    out.append(
        f"SUMMARY compared={len(both)} changed={changed} "
        f"unchanged={len(both) - changed} "
        f"classChanged={sum(1 for r in both if r['classChanged'])} "
        f"totalsChanged={sum(1 for r in both if r['totalsChanged'])} "
        f"onlyA={sum(1 for r in rows if r['status'] == 'only-A')} "
        f"onlyB={sum(1 for r in rows if r['status'] == 'only-B')}")
    for label, runkey in ((label_a, "a"), (label_b, "b")):
        counts = {c: 0 for c in CLASSES}
        for r in rows:
            if r[runkey] is not None:
                counts[r[runkey]["class"]] += 1
        out.append(f"CLASSES {label}: " + " ".join(
            f"{c}={counts[c]}" for c in CLASSES))
    if transitions:
        out.append("TRANSITIONS " + " ".join(
            f"{k}={v}" for k, v in sorted(transitions.items())))
    by_case = {r["case"]: r for r in rows}
    for name in focus:
        r = by_case.get(name)
        if r is None:
            out.append(f"FOCUS {name}: not present in either run")
        elif r["status"] != "both":
            out.append(f"FOCUS {name}: {r['status']}")
        else:
            out.append(
                f"FOCUS {name}: class {r['a']['class']} -> "
                f"{r['b']['class']} ({'changed' if r['classChanged'] else 'same'})"
                f", {label_b} closed={'yes' if r['b']['class'] == 'closed' else 'no'}")
    out.extend(render_detail(rows, label_a, label_b))
    if coverage:
        out.append(coverage)
    out.append("STREAM-COMPARE-DONE")
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Compare two directories of harness *.stream.json dumps.")
    ap.add_argument("run_a")
    ap.add_argument("run_b")
    ap.add_argument("--label-a", default="A")
    ap.add_argument("--label-b", default="B")
    ap.add_argument("--focus", action="append", default=[],
                    help="case name to call out explicitly (repeatable)")
    ap.add_argument("--json", help="also write the per-case rows as JSON here")
    ap.add_argument("--expect", type=int, default=None,
                    help="expected case count per run; exit 3 if either "
                         "run has a different number of dumps")
    ns = ap.parse_args(argv)

    run_a, run_b = load_run(ns.run_a), load_run(ns.run_b)
    if not run_a and not run_b:
        print(f"stream_compare: no *{SUFFIX} files in either directory",
              file=sys.stderr)
        return 2
    rows = compare(run_a, run_b)
    coverage = None
    if ns.expect is not None:
        complete = len(run_a) == ns.expect and len(run_b) == ns.expect
        coverage = (f"COVERAGE {ns.label_a}={len(run_a)} {ns.label_b}={len(run_b)} "
                    f"expected={ns.expect} complete={'yes' if complete else 'no'}")
    sys.stdout.write(render(rows, ns.label_a, ns.label_b, ns.focus, coverage))
    if ns.json:
        pathlib.Path(ns.json).write_text(
            json.dumps(rows, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    if coverage and coverage.endswith("complete=no"):
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
