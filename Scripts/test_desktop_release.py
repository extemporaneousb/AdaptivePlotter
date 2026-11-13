#!/usr/bin/env python3
"""Exercise publication in isolated homes without launching either application."""
import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).with_name('publish_desktop_apps.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class DesktopReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.home = self.root / 'home'
        self.destination = self.home / 'Desktop/AdaptivePlotter'
        for product in publisher.PRODUCTS:
            self.bundle(self.source, product, 'new')
        self.run_patch = patch.object(publisher.subprocess, 'run', side_effect=self.run_command)
        self.run_patch.start()
        self.addCleanup(self.run_patch.stop)
        self.validation = patch.object(publisher, 'validate')
        self.validation.start()
        self.addCleanup(self.validation.stop)

    def bundle(self, directory, product, generation):
        bundle = directory / f'{product}.app'
        (bundle / 'Contents/Resources').mkdir(parents=True)
        (bundle / 'Contents/MacOS').mkdir()
        (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': f'com.bullard.{product}', f'{product}BuildConfiguration': 'release'}))
        (bundle / 'Contents/MacOS' / product).write_text(generation)
        (bundle / f'Contents/Resources/{product}.icns').write_bytes(b'icns' + product.encode())
        return bundle

    def run_command(self, argv, **kwargs):
        if argv[0] == '/usr/bin/ditto':
            shutil.copytree(argv[1], argv[2])
            return subprocess.CompletedProcess(argv, 0)
        self.assertEqual(argv[0], '/usr/sbin/lsof')
        return subprocess.CompletedProcess(argv, 1, stdout=b'', stderr=b'')

    def publish(self):
        publisher.publish(self.source, self.home)

    def generation(self, product):
        return (self.destination / f'{product}.app/Contents/MacOS/{product}').read_text()

    def test_publish_and_repeat_preserve_history_and_links(self):
        self.destination.mkdir(parents=True)
        history = self.destination / 'verification.txt'
        history.write_text('retained')
        for product in publisher.PRODUCTS:
            self.bundle(self.destination, product, 'old')
        self.publish()
        self.publish()
        self.assertEqual(history.read_text(), 'retained')
        for product, label in publisher.PRODUCTS.items():
            self.assertEqual(self.generation(product), 'new')
            self.assertEqual((self.home / 'Desktop' / label).resolve(), (self.destination / f'{product}.app').resolve())

    def test_unrelated_desktop_item_refused_before_refresh(self):
        (self.home / 'Desktop').mkdir(parents=True)
        item = self.home / 'Desktop/Portrait Studio.app'
        item.write_text('unrelated')
        with self.assertRaisesRegex(RuntimeError, 'unrelated Desktop'):
            self.publish()
        self.assertEqual(item.read_text(), 'unrelated')
        self.assertFalse((self.destination / 'AdaptivePlotter.app').exists())

    def test_running_bundle_refused(self):
        self.bundle(self.destination, 'AdaptivePlotter', 'old')
        with patch.object(publisher.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)):
            with self.assertRaisesRegex(RuntimeError, 'Quit AdaptivePlotter'):
                self.publish()
        self.assertEqual(self.generation('AdaptivePlotter'), 'old')

    def test_unknown_running_state_refused(self):
        self.bundle(self.destination, 'AdaptivePlotter', 'old')
        with patch.object(publisher.subprocess, 'run', return_value=subprocess.CompletedProcess([], 2, stderr=b'error')):
            with self.assertRaisesRegex(RuntimeError, 'Cannot establish'):
                self.publish()

    def test_second_product_failure_restores_both_then_retry_succeeds(self):
        for product in publisher.PRODUCTS:
            self.bundle(self.destination, product, 'old')
        real_replace = publisher.os.replace
        failed = False

        def fail_once(source, target):
            nonlocal failed
            if not failed and source.name == 'PortraitStudio.app' and source.parent.name.startswith('.release-'):
                failed = True
                raise OSError('injected second-product rename failure')
            return real_replace(source, target)

        with patch.object(publisher.os, 'replace', side_effect=fail_once):
            with self.assertRaisesRegex(OSError, 'injected'):
                self.publish()
        for product in publisher.PRODUCTS:
            self.assertEqual(self.generation(product), 'old')
        self.assertFalse((self.destination / '.release-transaction.json').exists())
        self.publish()
        for product in publisher.PRODUCTS:
            self.assertEqual(self.generation(product), 'new')

    def test_missing_second_source_does_not_mutate_first(self):
        self.bundle(self.destination, 'AdaptivePlotter', 'old')
        shutil.rmtree(self.source / 'PortraitStudio.app')
        with self.assertRaises(FileNotFoundError):
            self.publish()
        self.assertEqual(self.generation('AdaptivePlotter'), 'old')

    def test_identical_icons_refused(self):
        icons = [self.source / f'{p}.app/Contents/Resources/{p}.icns' for p in publisher.PRODUCTS]
        icons[1].write_bytes(icons[0].read_bytes())
        with self.assertRaisesRegex(RuntimeError, 'distinct icon'):
            self.publish()
        self.assertFalse((self.destination / 'AdaptivePlotter.app').exists())

    def test_interrupted_publication_recovers_before_next_attempt(self):
        import json
        self.destination.mkdir(parents=True)
        stage = self.destination / '.release-interrupted'
        stage.mkdir()
        for product in publisher.PRODUCTS:
            self.bundle(stage, product, 'new')
            self.bundle(self.destination, product, 'old')
        target = self.destination / 'AdaptivePlotter.app'
        target.rename(stage / 'AdaptivePlotter.old.app')
        (stage / 'AdaptivePlotter.app').rename(target)
        (self.destination / '.release-transaction.json').write_text(json.dumps({'stage': str(stage), 'new_links': {}}))
        # A subsequent bad source causes preflight to stop after recovery.
        with patch.object(publisher, 'validate', side_effect=RuntimeError('bad source')):
            with self.assertRaisesRegex(RuntimeError, 'bad source'):
                self.publish()
        for product in publisher.PRODUCTS:
            self.assertEqual(self.generation(product), 'old')
        self.publish()
        for product in publisher.PRODUCTS:
            self.assertEqual(self.generation(product), 'new')

    def test_direct_publication_refuses_debug_bundle(self):
        self.validation.stop()
        bundle = self.source / 'AdaptivePlotter.app'
        plist = bundle / 'Contents/Info.plist'
        values = plistlib.loads(plist.read_bytes())
        values['AdaptivePlotterBuildConfiguration'] = 'debug'
        plist.write_bytes(plistlib.dumps(values))
        with self.assertRaisesRegex(RuntimeError, 'optimized release'):
            self.publish()
        self.assertFalse((self.destination / 'AdaptivePlotter.app').exists())

    def test_interrupted_rollback_is_idempotent(self):
        import json
        self.destination.mkdir(parents=True)
        stage = self.destination / '.release-interrupted-rollback'
        stage.mkdir()
        for product in publisher.PRODUCTS:
            self.bundle(stage, product, 'new')
            self.bundle(self.destination, product, 'old')
        # Rollback has already moved the new app back into staging and restored
        # the old app. Retained journal must not delete the restored app on retry.
        (self.destination / '.release-transaction.json').write_text(json.dumps({'stage': str(stage), 'new_links': {}}))
        with patch.object(publisher, 'validate', side_effect=RuntimeError('bad source')):
            with self.assertRaisesRegex(RuntimeError, 'bad source'):
                self.publish()
        for product in publisher.PRODUCTS:
            self.assertEqual(self.generation(product), 'old')


if __name__ == '__main__':
    unittest.main()
