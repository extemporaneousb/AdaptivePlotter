#!/usr/bin/env python3
"""Check the normative schema and its design fixtures with a development-only validator."""
import json
from pathlib import Path
from zipfile import ZipFile

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "Resources/DrawingExchange/v1/schema.json"
FIXTURE = ROOT / "Tests/Fixtures/DrawingExchange/v1/source-free.zip"


def main():
    schema = json.loads(SCHEMA.read_bytes())
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    examples = [record for entry in schema["$defs"].values() for record in entry.get("examples", [])]
    for record in examples:
        validator.validate(record)
    with ZipFile(FIXTURE) as package:
        for name in package.namelist():
            if name == "data/exchange.json" or name.endswith("/drawing.json"):
                validator.validate(json.loads(package.read(name)))

    result = next(r for r in examples if r.get("kind") == "result" and r["attempts"] == [])
    refused = next(r for r in examples if r.get("disposition") == "refused")
    accepted = next(r for r in examples if r.get("disposition") == "accepted")
    invalid = {
        "receipt missing": {k: v for k, v in result.items() if k != "jobs"},
        "empty job list": {**result, "jobs": []},
        "receipt digest missing": {
            **result, "jobs": [{k: v for k, v in result["jobs"][0].items() if k != "receiptDigest"}]
        },
        "refused with issuance": {**refused, "issuance": accepted["issuance"]},
        "accepted without issuance": {k: v for k, v in accepted.items() if k != "issuance"},
        "result without authored revision": {**result, "roots": []},
    }
    for label, record in invalid.items():
        if validator.is_valid(record):
            raise ValueError(f"Schema admitted invalid example: {label}")
    print(f"DX-0001 schema passed: {len(examples)} examples, {len(invalid)} refusals and fixture envelopes")


if __name__ == "__main__":
    main()
