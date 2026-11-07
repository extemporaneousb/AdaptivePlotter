#!/usr/bin/env python3
"""Check the frozen source-free Drawing Exchange v1 design example.

This is an example-specific golden conformance check, not a production exchange
codec or a general-purpose ZIP/BagIt validator. Optional PATH permits checking a
corrupted copy without modifying the committed fixture. No extraction occurs.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys
import unicodedata
import uuid
import zipfile


DRAWING_HASH = "e6f9f570fa580fa59cb5f6f3435641aa5c5c3acbcc4eeb944f3a606fe0b55ddd"
PROGRAM_HASH = "960ce7fe5f34203bdaa451fbd48f401cdb34598bebcb3a8be7a739645f236097"
PROGRAM_OBJECT = "6fb592aedc29e2909cc9eb7106fa40699c53ef5783695a8ef8a663c6e11d89b1"
RECEIPT_OBJECT = "20e72ed1a6ea86a0fff6ed88be9df8eb4756dcb9774618a09ea1f3aa68e7de33"
REF = {"issuer": "550e8400-e29b-41d4-a716-446655440000",
       "revision": "e95e1607-a025-4598-880a-221077f27cc1"}
DRAWING_PATH = f"data/drawings/{REF['issuer']}/{REF['revision']}/drawing.json"
OBJECT_PREFIX = "data/objects/sha256/"
PAYLOAD = {DRAWING_PATH, "data/exchange.json",
           OBJECT_PREFIX + PROGRAM_OBJECT, OBJECT_PREFIX + RECEIPT_OBJECT}
TAGS = {"bagit.txt", "manifest-sha256.txt", "tagmanifest-sha256.txt"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def decode_json(data):
    def reject_constant(value):
        raise ValueError(f"non-finite JSON number: {value}")
    return json.loads(data.decode("utf-8"), object_pairs_hook=unique_object,
                      parse_constant=reject_constant)


def manifest(data, expected, files):
    entries = {}
    for line in data.decode("utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        require(match is not None, "malformed SHA256 manifest line")
        digest, name = match.groups()
        require(name not in entries, f"duplicate manifest entry: {name}")
        entries[name] = digest
    require(set(entries) == expected, "manifest membership is not closed")
    for name, digest in entries.items():
        require(sha256(files[name]) == digest, f"manifest digest mismatch: {name}")
    return entries


def program_digest(program):
    """Independent port of DrawingProgramHashBasis + CanonicalEncoder schema 1.

    Match Sources/PlotterModel/{CanonicalEncoding,DrawingProgram,Geometry}.swift:
    big endian integers/finite doubles, NFC UTF-8 strings with UInt32 lengths,
    raw UUID bytes, ordered strokes. contentHash is NOT part of its own basis.
    """
    encoded = bytearray(b"APCB" + struct.pack(">H", 1))

    def integer(value, code, maximum):
        require(type(value) is int and 0 <= value <= maximum, "invalid APCB integer")
        encoded.extend(struct.pack(code, value))

    def count(value):
        integer(value, ">I", 0xffffffff)

    def double(value):
        require(type(value) in (int, float) and math.isfinite(value),
                "invalid APCB double")
        encoded.extend(struct.pack(">d", 0.0 if value == 0 else value))

    def string(value):
        require(type(value) is str, "invalid APCB string")
        raw = unicodedata.normalize("NFC", value).encode("utf-8")
        count(len(raw))
        encoded.extend(raw)

    def identity(value):
        require(set(value) == {"rawValue"}, "invalid strong ID")
        encoded.extend(uuid.UUID(value["rawValue"]).bytes)

    string("DrawingProgram")
    identity(program["id"])
    integer(program["schemaVersion"], ">H", 0xffff)
    require(program["schemaVersion"] == 1, "unsupported program schema")
    extent = program["fieldExtent"]
    double(extent["width"])
    double(extent["height"])
    strokes = sorted(program["strokes"], key=lambda stroke: stroke["ordering"])
    count(len(strokes))
    for stroke in strokes:
        identity(stroke["id"])
        points = stroke["path"]["points"]
        count(len(points))
        for point in points:
            double(point["x"])
            double(point["y"])
        double(stroke["style"]["nominalLineWidth"])
        identity(stroke["style"]["penProfileID"])
        integer(stroke["semanticRole"], ">B", 0xff)
        integer(stroke["ordering"], ">I", 0xffffffff)
    string(program["source"]["kind"])
    string(program["source"]["sourceIdentifier"])
    return sha256(encoded)


def check(path):
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        require(len(names) == len(set(names)), "duplicate ZIP member")
        require(set(names) == PAYLOAD | TAGS, "unexpected or missing ZIP member")
        require(all(entry.file_size <= 1_000_000 for entry in entries),
                "example ZIP member exceeds size bound")
        files = {name: archive.read(name) for name in names}
    require(files["bagit.txt"] ==
            b"BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n",
            "unexpected BagIt declaration")
    payload_manifest = manifest(files["manifest-sha256.txt"], PAYLOAD, files)
    manifest(files["tagmanifest-sha256.txt"], TAGS - {"tagmanifest-sha256.txt"}, files)
    exchange = decode_json(files["data/exchange.json"])
    require(exchange["profile"] == "adaptiveplotter.exchange/1" and
            exchange["kind"] == "drawing", "unexpected exchange profile/kind")
    require(exchange["roots"] == [{**REF, "digest": DRAWING_HASH}],
            "unexpected root reference/digest")
    require(exchange["attempts"] == [] and exchange["assessments"] == [],
            "example must not include attempts or assessments")
    require(payload_manifest[DRAWING_PATH] == DRAWING_HASH,
            "drawing manifest differs from reviewed golden")
    drawing = decode_json(files[DRAWING_PATH])
    require(drawing["ref"] == REF and drawing["profile"] == "adaptiveplotter.drawing/1",
            "drawing reference/profile mismatch")
    require(drawing["input"] == {"state": "none"} and
            drawing["parent"] == {"state": "none"}, "example is not source-free")
    require(drawing["requiredFeatures"] == [], "unexpected required features")
    require(drawing["representation"] == {
        "kind": "adaptiveplotter.stroke-program/1", "object": PROGRAM_OBJECT,
        "programHash": PROGRAM_HASH}, "unexpected representation")
    require(drawing["producer"] == {"id": "adaptiveplotter.catalog", "version": "1",
                                     "record": RECEIPT_OBJECT}, "unexpected producer")
    assets = exchange["assets"]
    expected_assets = {
        PROGRAM_OBJECT: (605, "adaptiveplotter.stroke-program/1"),
        RECEIPT_OBJECT: (139, "adaptiveplotter.example.catalog-receipt/1")}
    require(len(assets) == 2 and {a["object"] for a in assets} == set(expected_assets),
            "unexpected asset membership")
    for asset in assets:
        object_hash = asset["object"]
        length, encoding = expected_assets[object_hash]
        data = files[OBJECT_PREFIX + object_hash]
        require(type(asset["byteLength"]) is int and
                asset["byteLength"] == len(data) == length, "asset length mismatch")
        require(sha256(data) == object_hash, "asset object hash mismatch")
        require(asset["mediaType"] == "application/json" and
                asset["encoding"] == encoding, "asset profile mismatch")
    receipt = decode_json(files[OBJECT_PREFIX + RECEIPT_OBJECT])
    require(receipt == {"entry": "line", "fixture": True,
                       "profile": "adaptiveplotter.example.catalog-receipt/1",
                       "sourceIdentifier": "adaptiveplotter.builtin.line.v1"},
            "unexpected catalog receipt")
    program = decode_json(files[OBJECT_PREFIX + PROGRAM_OBJECT])
    require(program["fieldExtent"] == {"width": 100, "height": 100} and
            len(program["strokes"]) == 1, "unexpected catalog-line field/strokes")
    stroke = program["strokes"][0]
    require(stroke["path"] == {"points": [{"x": 5, "y": 50}, {"x": 95, "y": 50}]},
            "catalog line coordinates changed")
    require(stroke["ordering"] == 0 and stroke["semanticRole"] == 0 and
            stroke["style"]["nominalLineWidth"] == 0.5, "catalog-line style changed")
    require(program["source"] == {"kind": "built-in-vector-catalog",
                                   "sourceIdentifier": "adaptiveplotter.builtin.line.v1"},
            "unexpected program provenance")
    embedded = program["contentHash"]["bytes"]
    require(type(embedded) is list and len(embedded) == 32 and
            all(type(n) is int and 0 <= n <= 255 for n in embedded),
            "invalid embedded program digest")
    require(bytes(embedded).hex() == program_digest(program) == PROGRAM_HASH,
            "independent APCB program digest differs from embedded/reviewed golden")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", type=Path,
                        default=Path(__file__).resolve().parents[1] /
                        "Tests/Fixtures/DrawingExchange/v1/source-free.zip")
    args = parser.parse_args()
    try:
        check(args.path)
    except (OSError, ValueError, KeyError, TypeError, IndexError, OverflowError,
            struct.error, zipfile.BadZipFile, RuntimeError, NotImplementedError) as error:
        print(f"Drawing Exchange golden fixture FAILED: {error}", file=sys.stderr)
        return 1
    print("Drawing Exchange source-free golden fixture passed (independent APCB digest)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
