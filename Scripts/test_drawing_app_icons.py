#!/usr/bin/env python3
"""Reject missing, altered, and incorrectly declared icon resources in both apps."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
bundles = Path(sys.argv[1]) if len(sys.argv) > 1 else root / '.build'
with tempfile.TemporaryDirectory(prefix='drawing-icon-validation-') as directory:
    for product in ('AdaptivePlotter', 'PortraitStudio'):
        source = bundles / f'{product}.app'
        validator = root / 'Scripts' / ('validate_local_app_bundle.sh' if product == 'AdaptivePlotter' else 'validate_portrait_studio_app_bundle.sh')
        subprocess.run(['sh', str(validator), str(source)], check=True)
        for failure in ('missing', 'altered', 'declaration'):
            target = Path(directory) / f'{product}-{failure}.app'
            shutil.copytree(source, target)
            icon = target / f'Contents/Resources/{product}.icns'
            if failure == 'missing':
                icon.unlink()
            elif failure == 'altered':
                icon.write_bytes(icon.read_bytes() + b'tampered')
            else:
                plist = target / 'Contents/Info.plist'
                values = plistlib.loads(plist.read_bytes())
                values['CFBundleIconFile'] = 'OtherProduct.icns'
                plist.write_bytes(plistlib.dumps(values))
            result = subprocess.run(['sh', str(validator), str(target)], capture_output=True)
            if result.returncode == 0:
                raise SystemExit(f'{product} accepted {failure} icon resource')
print('Both app validators reject missing, altered, and incorrectly declared icons')
