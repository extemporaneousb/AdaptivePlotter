#!/usr/bin/env python3
"""Test signing, output overrides and Desktop publication using disposable Mach-O fixtures."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent

def run(*argv, **kwargs):
    subprocess.run(argv, cwd=root, check=True, **kwargs)

with tempfile.TemporaryDirectory(prefix='drawing-packaging-') as directory:
    fixture = Path(directory)
    (fixture / 'bin').mkdir()
    (fixture / 'bundles').mkdir()
    for number, product in enumerate(('AdaptivePlotter', 'PortraitStudio')):
        source = fixture / f'{product}.c'
        source.write_text(f'int main(void) {{ return {number}; }}\n')
        run('xcrun', 'clang', str(source), '-o', str(fixture / 'bin' / product))
        builder = 'build_local_app.sh' if number == 0 else 'build_portrait_studio_app.sh'
        environment = dict(os.environ, APP_BINARY_DIRECTORY=str(fixture / 'bin'),
                           ADAPTIVEPLOTTER_CODESIGN_IDENTITY='-', PORTRAITSTUDIO_CODESIGN_IDENTITY='-')
        run('sh', str(root / 'Scripts' / builder), 'release', str(fixture / 'bundles' / f'{product}.app'), env=environment)
    run('sh', 'Scripts/test_drawing_app_build_inputs.sh', str(fixture / 'bin'), 'release', str(fixture / 'bundles'))
    for _ in range(2):
        run('python3', 'Scripts/publish_desktop_apps.py', '--source', str(fixture / 'bundles'), '--home', str(fixture / 'home'))
    run('sh', 'Scripts/test_local_app_bundle_validation.sh', str(fixture / 'bundles/AdaptivePlotter.app'))
print('Disposable two-app packaging and publication checks passed; no applications launched')
