"""Deterministic checks on the arbiter fixture corpus and verdict contract.
No LLM call — this is the gating test. The live-model calibration lives in
afk-arbiter-calibrate.py and is explicitly non-gating."""
import json
from pathlib import Path

FIX = Path(__file__).parent / "arbiter-fixtures"
DIAGNOSES = {"critic-false-positive", "unsatisfiable-constraint",
             "goal-criterion-defect", "other"}
VERDICTS = {"override-critic", "relax-to-resolution", "escalate-human"}


def load():
    return [json.loads(p.read_text()) for p in sorted(FIX.glob("prd-*.json"))]


def test_three_fixtures_present():
    assert len(load()) == 3


def test_fixture_shape_and_values():
    for fx in load():
        assert isinstance(fx["prd"], int)
        assert fx["prd_body"].strip()
        assert fx["rejection_history"].strip()
        assert fx["expected"]["diagnosis"] in DIAGNOSES
        assert fx["expected"]["verdict"] in VERDICTS


def test_expected_verdicts_obey_invariants():
    for fx in load():
        d, v = fx["expected"]["diagnosis"], fx["expected"]["verdict"]
        if d == "goal-criterion-defect":
            assert v == "escalate-human", f"PRD {fx['prd']} violates GOAL.md boundary"


def test_all_three_categories_covered():
    diags = {fx["expected"]["diagnosis"] for fx in load()}
    assert {"critic-false-positive", "unsatisfiable-constraint",
            "goal-criterion-defect"} <= diags


if __name__ == "__main__":
    import sys
    fns = [g for n, g in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn(); print(f"PASS {fn.__name__}")
    print("ALL PASS")
