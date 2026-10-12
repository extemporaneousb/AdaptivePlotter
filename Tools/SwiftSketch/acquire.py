#!/usr/bin/env python3
"""Fetch externally, verify pinned hashes, extract inference assets only."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
from worker import OFFICIAL_ASSET_SHA256, OFFICIAL_PIN_FILE_SHA256, UPSTREAM_COMMIT


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--upstream-root", required=True)
    args = parser.parse_args()
    directory = Path(args.directory).resolve()
    root = Path(args.upstream_root).resolve()
    repo = Path(__file__).resolve().parents[2]
    if directory == repo or repo in directory.parents or root == repo or repo in root.parents:
        raise ValueError("upstream and weights must remain outside the repository")
    pin_file = Path(__file__).with_name("model-pins.json")
    if sha(pin_file) != OFFICIAL_PIN_FILE_SHA256:
        raise ValueError("official pin file identity differs from trusted adapter")
    pins = json.loads(pin_file.read_text())
    if pins["upstream_commit"] != UPSTREAM_COMMIT or any(pins["assets"][key]["sha256"] != value for key, value in OFFICIAL_ASSET_SHA256.items()):
        raise ValueError("official pin declaration differs from trusted adapter")
    directory.mkdir(parents=True, exist_ok=True)
    if not root.exists():
        subprocess.run(["git", "clone", "--no-checkout", pins["upstream_url"], str(root)], check=True, timeout=120)
        subprocess.run(["git", "-C", str(root), "checkout", "--detach", pins["upstream_commit"]], check=True, timeout=60)
    if subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip() != pins["upstream_commit"]:
        raise ValueError("existing upstream checkout pin differs; preserve it")
    for kind in ("diffusion", "refinement"):
        archive = directory/(kind+".zip")
        if not archive.exists():
            subprocess.run([sys.executable, "-m", "gdown", pins["assets"][kind]["archive_url"], "-O", str(archive)], check=True, timeout=240)
        if archive.stat().st_size > 512*1024**2:
            raise ValueError("model archive exceeds download bound")
        with zipfile.ZipFile(archive) as zipped:
            for key in (kind, kind+"_args"):
                asset = pins["assets"][key]
                member = zipped.getinfo(asset["member"])
                if member.file_size > 256*1024**2 or Path(member.filename).is_absolute() or ".." in Path(member.filename).parts:
                    raise ValueError("invalid archive member")
                target = directory/member.filename
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists():
                    with zipped.open(member) as source, target.open("xb") as dest:
                        shutil.copyfileobj(source, dest, length=1024*1024)
                if sha(target) != asset["sha256"]:
                    raise ValueError("checkpoint or args pin mismatch: "+key)
    clip = directory/"RN101.pt"
    if not clip.exists():
        subprocess.run(["curl", "-fL", "--max-time", "240", "--max-filesize", str(512*1024**2),
                        pins["assets"]["clip"]["url"], "-o", str(clip)], check=True, timeout=245)
    if sha(clip) != pins["assets"]["clip"]["sha256"]:
        raise ValueError("CLIP pin mismatch")
    manifest = {"schema_version": 1, "upstream_root": str(root), "upstream_commit": pins["upstream_commit"],
        "assets": {key: {"path": str(directory/asset["member"]), "sha256": asset["sha256"]} for key, asset in pins["assets"].items()},
        "license_status": pins["license_status"]}
    path = directory/"manifest.json"
    if path.exists():
        raise ValueError("manifest exists; preserve its exact bytes and use it")
    path.write_text(json.dumps(manifest, sort_keys=True))
    print(json.dumps({"manifest_path": str(path), "manifest_sha256": sha(path)}, sort_keys=True))


if __name__ == "__main__":
    main()
