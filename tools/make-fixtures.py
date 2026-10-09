#!/usr/bin/env python3
# Writes tests/testthat/fixtures/python-msgpack.tsv: MessagePack written by
# Python's msgpack at a pinned version (design section 15), one row per
# object, with Python's own decoding of it in the canonical text form of
# tools/canon.py. The R tests decode each row and compare, so they need no
# Python. Run by tools/update-fixtures; usage, from the package root:
#
#   python3 -I tools/make-fixtures.py <output.tsv>
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import msgpack  # noqa: E402
from canon import canon, unpack_all  # noqa: E402

PINNED = (1, 1, 1)
if msgpack.version != PINNED:
    sys.exit("make-fixtures: msgpack %s is pinned, %s is installed"
             % (".".join(map(str, PINNED)), ".".join(map(str, msgpack.version))))

T = msgpack.Timestamp
X = msgpack.ExtType
rows = []


def add(name, obj, **kw):
    data = msgpack.packb(obj, **kw)
    got = unpack_all(data)
    assert len(got) == 1, name
    rows.append((name, data.hex(), canon(got[0])))


ints = [0, 1, 127, 128, 255, 256, 65535, 65536, 2**32 - 1, 2**32, 2**53, 2**53 + 1,
        2**63 - 1, 2**63, 2**64 - 1, -1, -32, -33, -128, -129, -32768, -32769,
        -2**31, -2**31 - 1, -2**53, -2**53 - 1, -2**63]
for v in ints:
    add("int %d" % v, v)
for v in [0.0, -0.0, 1.5, 0.1, 1e300, 5e-324, float("inf"), float("-inf"), float("nan")]:
    add("float64 %r" % v, v)
for v in [0.5, 1.5, 3.4028234663852886e38, float("nan"), float("-inf")]:
    add("float32 %r" % v, v, use_single_float=True)
add("nil", None)
add("true", True)
add("false", False)
for n in [0, 1, 31, 32, 255, 256, 300]:
    add("str %d" % n, "x" * n)
add("str utf8", "ü水\U0001f600 €")
for n in [0, 1, 255, 256, 300]:
    add("bin %d" % n, bytes(i % 256 for i in range(n)))
for n in [0, 1, 15, 16, 300]:
    add("array %d" % n, list(range(n)))
add("array mixed", [1, "a", None, True, 1.5, b"\x00", [1, [2]], {"k": "v"}])
add("map empty", {})
add("map str", {"a": 1, "b": [1, 2], "c": {"d": None}})
add("map 16", {"k%02d" % i: i for i in range(16)})
add("map int keys", {1: "a", -1: "b", 2**40: "c"})
add("map mixed keys", {None: 1, True: 2, 1.5: 3, b"\x01": 4, (1, 2): 5, "s": 6})
for n in [1, 2, 4, 8, 16, 0, 3, 17, 256]:
    add("ext 5 len %d" % n, X(5, bytes(i % 256 for i in range(n))))
# Python's ExtType takes types 0 to 127 only: the negative ones are
# reserved, so the suite and our own tests cover those.
add("ext 127", X(127, b""))
for s, ns in [(0, 0), (1, 0), (2**32 - 1, 0), (2**32, 0), (1514862245, 678901234),
              (2**34 - 1, 999999999), (2**34, 0), (-1, 0), (-1, 999999999),
              (-62167219200, 0), (253402300799, 999999999)]:
    add("timestamp %d %d" % (s, ns), T(s, ns))
add("records", [{"id": 1, "name": "a", "score": 1.5},
                {"id": 2, "name": "b"},
                {"id": 3, "score": None, "tags": ["x", "y"]}])

# Fluentd's forward protocol, forward mode: [tag, [[time, record], ...]],
# with time as an EventTime (ext type 0: 32-bit seconds, 32-bit
# nanoseconds), messages back to back on the wire.
def event_time(s, ns):
    return X(0, s.to_bytes(4, "big") + ns.to_bytes(4, "big"))


stream = b"".join(msgpack.packb(m) for m in [
    ["app.access", [[event_time(1700000000, 123456789), {"path": "/", "status": 200}],
                    [event_time(1700000001, 0), {"path": "/x", "status": 404}]]],
    ["app.error", [[1700000002, {"message": "oops", "level": "error"}]], {"chunk": "abc"}],
])
objs = unpack_all(stream)
rows.append(("fluentd forward stream", stream.hex(), ";".join(canon(o) for o in objs)))

with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as f:
    f.write("name\thex\tcanon\n")
    for name, h, c in rows:
        f.write("%s\t%s\t%s\n" % (name, h, c))
print("==> %d rows from Python msgpack %s" % (len(rows), ".".join(map(str, msgpack.version))))
