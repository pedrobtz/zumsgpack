# The canonical text form of a decoded MessagePack value, shared with R
# (tools/canon.R and tests/testthat/helper-canon.R write the same): two
# implementations agree on a value exactly when they print the same text.
#
#   nil        null            true, false   true, false
#   number     n:<16 hex digits of the IEEE 754 double>, for every float
#              and every integer within 2^53 in magnitude; i:<decimal>
#              for a wider integer (the two languages' integer and float
#              types do not line up, their values do)
#   str        s:<hex of the UTF-8 bytes>     bin   b:<hex>
#   array      [<a>,<b>,...]                  map   {<k>=<v>,...} in order
#   ext        x:<type>:<hex>                 timestamp   t:<sec>:<nsec>
import struct

import msgpack


def canon(v):
    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, int):
        if abs(v) <= 2**53:
            return "n:" + struct.pack(">d", float(v)).hex()
        return "i:%d" % v
    if isinstance(v, float):
        return "n:" + struct.pack(">d", v).hex()
    if isinstance(v, str):
        return "s:" + v.encode("utf-8").hex()
    if isinstance(v, (bytes, bytearray)):
        return "b:" + bytes(v).hex()
    if isinstance(v, msgpack.Timestamp):
        return "t:%d:%d" % (v.seconds, v.nanoseconds)
    if isinstance(v, msgpack.ExtType):
        return "x:%d:%s" % (v.code, v.data.hex())
    if isinstance(v, MapPairs):
        return "{" + ",".join(canon(k) + "=" + canon(x) for k, x in v) + "}"
    if isinstance(v, (list, tuple)):
        return "[" + ",".join(canon(x) for x in v) + "]"
    raise TypeError("no canonical form for %r" % (v,))


class MapPairs(list):
    """A decoded map, kept as its pairs in order (object_pairs_hook)."""


def unpack_all(data):
    """Every object in data, maps as MapPairs, keys of any type allowed."""
    u = msgpack.Unpacker(None, raw=False, strict_map_key=False,
                         object_pairs_hook=MapPairs, timestamp=0,
                         max_buffer_size=max(len(data), 1024))
    u.feed(data)
    return list(u)
