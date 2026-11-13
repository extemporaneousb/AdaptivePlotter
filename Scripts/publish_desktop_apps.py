#!/usr/bin/env python3
"""Refresh the two stable Desktop bundles, with a retryable rollback journal."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile

PRODUCTS = {'AdaptivePlotter': 'AdaptivePlotter.app', 'PortraitStudio': 'Portrait Studio.app'}
ROOT = Path(__file__).resolve().parent.parent


def validate(bundle, product):
    with (bundle / 'Contents/Info.plist').open('rb') as stream:
        if plistlib.load(stream).get(f'{product}BuildConfiguration') != 'release':
            raise RuntimeError(f'{product} Desktop publication requires an optimized release bundle')
    script = 'validate_local_app_bundle.sh' if product == 'AdaptivePlotter' else 'validate_portrait_studio_app_bundle.sh'
    subprocess.run(['sh', str(ROOT / 'Scripts' / script), str(bundle)], check=True)


def guard_bundle(bundle, product):
    if bundle.is_symlink():
        raise RuntimeError(f'refusing symbolic-link bundle: {bundle}')
    if bundle.exists():
        with (bundle / 'Contents/Info.plist').open('rb') as stream:
            if plistlib.load(stream).get('CFBundleIdentifier') != f'com.bullard.{product}':
                raise RuntimeError(f'refusing unrelated bundle: {bundle}')
        running = subprocess.run(['/usr/sbin/lsof', '-t', str(bundle / 'Contents/MacOS' / product)], capture_output=True)
        if running.returncode == 0:
            raise RuntimeError(f'Quit {product} normally before refreshing its Desktop bundle')
        if running.returncode != 1:
            raise RuntimeError(f'Cannot establish whether {product} is running: {running.stderr.decode()}')


def publish(source, home):
    desktop = home / 'Desktop'
    destination = desktop / 'AdaptivePlotter'
    desktop.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        raise RuntimeError(f'refusing symbolic-link release directory: {destination}')
    destination.mkdir(exist_ok=True)
    with (destination / '.release.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        journal = destination / '.release-transaction.json'

        def rollback():
            if not journal.exists():
                return
            state = json.loads(journal.read_text())
            stage = Path(state['stage'])
            if stage.parent != destination or not stage.name.startswith('.release-'):
                raise RuntimeError('Invalid retained release transaction')
            for product in PRODUCTS:
                target = destination / f'{product}.app'
                guard_bundle(target, product)
                backup = stage / f'{product}.old.app'
                # A missing staged new bundle means it was already published.
                if not (stage / f'{product}.app').exists() and target.exists():
                    os.replace(target, stage / f'{product}.app')
                if backup.exists():
                    os.replace(backup, target)
            for name in state['new_links']:
                link = desktop / name
                if link.is_symlink() and os.readlink(link) == str(destination / f"{state['new_links'][name]}.app"):
                    link.unlink()
            journal.unlink()
            shutil.rmtree(stage)

        # Recover an interrupted publication before preparing a new generation.
        rollback()
        for product, label in PRODUCTS.items():
            validate(source / f'{product}.app', product)
            guard_bundle(destination / f'{product}.app', product)
            link = desktop / label
            expected = str(destination / f'{product}.app')
            if os.path.lexists(link) and not (link.is_symlink() and os.readlink(link) == expected):
                raise RuntimeError(f'refusing unrelated Desktop item: {link}')
        stage = Path(tempfile.mkdtemp(prefix='.release-', dir=destination))
        try:
            for product in PRODUCTS:
                subprocess.run(['/usr/bin/ditto', str(source / f'{product}.app'), str(stage / f'{product}.app')], check=True)
                validate(stage / f'{product}.app', product)
            icons = [(stage / f'{p}.app/Contents/Resources/{p}.icns').read_bytes() for p in PRODUCTS]
            if icons[0] == icons[1]:
                raise RuntimeError('The two applications must have distinct icon artwork')
            new_links = {label: product for product, label in PRODUCTS.items() if not os.path.lexists(desktop / label)}
            pending = destination / '.release-transaction.pending'
            pending.write_text(json.dumps({'stage': str(stage), 'new_links': new_links}))
            os.replace(pending, journal)
            for product in PRODUCTS:
                target = destination / f'{product}.app'
                guard_bundle(target, product)
                if target.exists():
                    os.replace(target, stage / f'{product}.old.app')
                os.replace(stage / f'{product}.app', target)
                validate(target, product)
            for product, label in PRODUCTS.items():
                link = desktop / label
                if not os.path.lexists(link):
                    link.symlink_to(destination / f'{product}.app')
            journal.unlink()  # Commit point: both applications and links are ready.
        except BaseException:
            rollback()
            raise
        finally:
            if not journal.exists():
                shutil.rmtree(stage, ignore_errors=True)
        for product, label in PRODUCTS.items():
            print(desktop / label)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / '.build')
    parser.add_argument('--home', type=Path, default=Path.home(), help='target home; use a disposable directory for tests')
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit('release interrupted'))
    publish(args.source.resolve(), args.home.resolve())


if __name__ == '__main__':
    main()
