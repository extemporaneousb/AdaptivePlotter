#!/usr/bin/env python3
"""External one-request supervisor:600s,2CPUthreads,6GiB RSS,8MiB log."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--python", required=True)
    parser.add_argument("--worker", required=True)
    parser.add_argument("--request", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=600)
    args = parser.parse_args()
    if not 0 < args.timeout <= 600:
        raise ValueError("timeout exceeds policy")
    output = Path(args.output)
    log = output.with_suffix(".log")
    if output.exists() or log.exists():
        raise ValueError("attempt exists; preserve it")
    command = [args.python, args.worker, "--request", args.request, "--manifest", args.manifest, "--output", args.output]
    environment = dict(os.environ, OMP_NUM_THREADS="2", MKL_NUM_THREADS="2", OPENBLAS_NUM_THREADS="2",
                       WANDB_DISABLED="true", HF_HUB_OFFLINE="1", PYTHONUNBUFFERED="1")
    start = time.monotonic()
    peak = 0
    reason = None
    with log.open("wb") as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=stream, env=environment)
        while process.poll() is None:
            observed = subprocess.run(["/bin/ps", "-o", "rss=", "-p", str(process.pid)], capture_output=True, text=True)
            if observed.stdout.strip():
                peak = max(peak, int(observed.stdout.strip()) * 1024)
            if peak > 6*1024**3:
                reason = "memory_limit"
            elif time.monotonic()-start > args.timeout:
                reason = "timeout"
            elif log.stat().st_size > 8*1024**2:
                reason = "log_limit"
            if reason:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                break
            time.sleep(0.25)
        code = process.wait()
    receipt = {"schema_version": 1, "argv": command, "returncode": code,
        "stop_reason": reason, "elapsed_seconds": time.monotonic()-start,
        "observed_peak_rss_bytes": peak, "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}
    output.with_suffix(".supervisor.json").write_text(json.dumps(receipt, sort_keys=True))
    print(json.dumps(receipt, sort_keys=True))
    return code if code >= 0 else 2


if __name__ == "__main__":
    sys.exit(main())
