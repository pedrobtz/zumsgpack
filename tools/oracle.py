#!/usr/bin/env python3
# The oracle (design section 15): Python's msgpack decodes every object in
# the table tools/conformance.R wrote and must print the same canonical form
# zumsgpack did. A difference is allowed only when a rule in
# tools/conformance-baselines.tsv attributes it, and the number each rule
# attributes must equal its baseline exactly: a rule that stops matching
# fails as surely as a new difference, so a baseline cannot hide anything
# by being generous (zuxml's W3C harness, zucbor's run-conformance).
#
#   python3 -I tools/oracle.py <table.tsv> <baselines.tsv>
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import msgpack  # noqa: E402
from canon import canon, unpack_all  # noqa: E402

# Each rule: a name, and a predicate over (row, Python's canonical form)
# saying whether the difference is the known one, with the reason.
RULES = {
    # The spec reserves ext types -128 to -2 for future extensions. Python's
    # ExtType refuses them on unpack ("code must be 0~127"); zumsgpack reads
    # them as msgpack_ext, so as not to break on a future spec (design 18 Q2).
    "python-refuses-reserved-ext": lambda row, py: (
        py.startswith("ERROR ValueError: code must be 0~127")
        and any(("x:%d:" % t) in row["canon"] for t in range(-128, -1))),
}


def main(table, baselines):
    want = {}
    with open(baselines, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            rule, count = line.split("\t")
            want[rule] = int(count)
    got = {rule: 0 for rule in want}
    unexplained = []
    n = 0
    with open(table, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            n += 1
            data = bytes.fromhex(row["hex"])
            try:
                objs = unpack_all(data)
                py = ";".join(canon(o) for o in objs)
            except Exception as e:  # Python refused what zumsgpack wrote or read
                py = "ERROR " + type(e).__name__ + ": " + str(e)
            if py == row["canon"]:
                continue
            rule = next((r for r, f in RULES.items() if f(row, py)), None)
            if rule is None:
                unexplained.append((row, py))
            else:
                got[rule] = got.get(rule, 0) + 1
    ok = True
    for row, py in unexplained:
        ok = False
        print("UNEXPLAINED %s %s:\n  zumsgpack %s\n  python    %s"
              % (row["source"], row["name"], row["canon"][:200], py[:200]))
    for rule in sorted(set(want) | set(got)):
        if got.get(rule, 0) != want.get(rule, 0):
            ok = False
            print("BASELINE %s: %d differences attributed, baseline says %d"
                  % (rule, got.get(rule, 0), want.get(rule, 0)))
    print("==> %d objects, %d unexplained, msgpack %s"
          % (n, len(unexplained), ".".join(map(str, msgpack.version))))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
