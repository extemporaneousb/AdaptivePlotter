#!/usr/bin/env python3
"""Write model availability only after a real successful, bounded local request."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    for name in ("python", "worker", "request", "manifest", "output", "proof"):
        parser.add_argument("--"+name, required=True)
    args = parser.parse_args()
    proof = Path(args.proof)
    if proof.exists():
        raise ValueError("proof exists; preserve it, choose a new receipt path")
    command = [sys.executable, str(Path(__file__).with_name("run_bounded.py")), "--python", args.python,
        "--worker", args.worker, "--request", args.request, "--manifest", args.manifest, "--output", args.output]
    subprocess.run(command, check=True, timeout=605)
    output = Path(args.output)
    response = json.loads((output/"response.json").read_text())
    request = json.loads(Path(args.request).read_text())
    provenance = json.loads((output/"provenance.json").read_text())
    if response["status"] != "succeeded" or response["request_id"] != request["request_id"] or provenance["adapter_sha256"] != sha(args.worker):
        raise ValueError("real inference proof identity mismatch")
    for name, digest in response["files"].items():
        if name not in ("raw-curves.json", "artist-input.png", "preview.png", "provenance.json") or sha(output/name) != digest:
            raise ValueError("proof asset hash mismatch")
    proof.write_text(json.dumps({"schema_version":1,"status":"succeeded",
        "adapter_sha256":sha(args.worker),"manifest_sha256":sha(args.manifest),
        "request_sha256":sha(args.request),"response_sha256":sha(output/"response.json"),
        "successful_attempts":[str(output/"response.json")],
        "inference_policy":"Pinned CPU tensor-only, caller-frozen square/no segmentation; quality unproven."}, sort_keys=True))
    print(json.dumps({"proof_path":str(proof),"proof_sha256":sha(proof)},sort_keys=True))


if __name__ == "__main__":
    main()
