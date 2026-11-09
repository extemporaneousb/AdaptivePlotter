#!/usr/bin/env python3
"""Measure the current active-fit/presentation paths using an existing normal test build.

Each condition uses the exact same sealed current-format fixture; each helper
clones it. No app process, production data or historical fixture is used.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time
from run_drawing_library_metadata_performance import inputs, write_json


def tree_pin(directory):
    return {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(directory.rglob('*')) if p.is_file()}


def stats(values):
    ordered = sorted(values)
    return {'samples': values, 'p50': ordered[math.ceil(len(ordered) * .5) - 1],
            'p95': ordered[math.ceil(len(ordered) * .95) - 1]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch-path', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--fixture-directory', type=Path)
    parser.add_argument('--baseline-directory', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    if not output.is_relative_to(Path(tempfile.gettempdir()).resolve()):
        parser.error('Output must be a new directory under the system temporary directory')
    output.mkdir(mode=0o700)
    fixture = args.fixture_directory.resolve(strict=True) if args.fixture_directory else output / 'sealed-current-fixture'
    scratch = args.scratch_path.resolve(strict=True)
    before = inputs(root)
    write_json(output / 'inputs-before.json', before)
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(('FLOW_', 'DRAWING_', 'DX_', 'PORTRAIT_', 'PLOTTER_', 'ADAPTIVEPLOTTER_')):
            del env[key]
    env['DRAWING_PRESENTATION_PERF'] = '1'
    env['DRAWING_PRESENTATION_PERF_FIXTURE'] = str(fixture)
    phases = ([] if args.fixture_directory else ['seed']) + ['warm'] + ['cold'] * 5
    reports = []
    fixture_before = tree_pin(fixture) if fixture.exists() else None
    for index, phase in enumerate(phases):
        name = f'{index:02d}-{phase}'
        report = output / f'{name}.json'
        argv = ['swift', 'test', '--skip-build', '--no-parallel', '--scratch-path', str(scratch),
                '--xunit-output', str(output / f'{name}.xml'), '--filter', 'DrawingPresentationPerformanceTests']
        env['DRAWING_PRESENTATION_PERF_PHASE'] = phase
        env['DRAWING_PRESENTATION_PERF_OUTPUT'] = str(report)
        started = time.time()
        with (output / f'{name}.log').open('wb') as log:
            result = subprocess.run(argv, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
        write_json(output / f'{name}-process.json', {'argv': argv, 'cwd': str(root), 'phase': phase,
            'startUnixSeconds': started, 'stopUnixSeconds': time.time(), 'exitCode': result.returncode})
        if result.returncode or not report.exists():
            raise SystemExit(result.returncode or 2)
        if phase == 'seed':
            fixture_before = tree_pin(fixture)
        else:
            reports.append(json.loads(report.read_text()))
    fixture_after = tree_pin(fixture)
    write_json(output / 'fixture-pin.json', fixture_after)
    after = inputs(root)
    write_json(output / 'inputs-after.json', after)
    operations = {}
    for report in reports:
        for sample in report['samples']:
            operations.setdefault(sample['operation'], []).append(sample['milliseconds'])
    metrics = {name: stats(values) for name, values in operations.items()}
    hashes = [r['beforeHashes'] for r in reports] + [r['afterHashes'] for r in reports]
    invariant = all(h == hashes[0] for h in hashes)
    receipt = {'format': 'drawing-presentation-performance-driver/1', 'fixtureDirectory': str(fixture),
        'operationsMilliseconds': metrics, 'geometryFeedbackHashes': hashes[0],
        'renderedPreviewPixelDigest': reports[0]['renderedPreviewPixelDigest'],
        'fixtureBytes': sum(p.stat().st_size for p in fixture.rglob('*') if p.is_file()),
        'sourceInputsUnchanged': before == after, 'sealedFixtureUnchanged': fixture_before == fixture_after,
        'geometryFeedbackUnchanged': invariant,
        'warmProcessLifetimePeakRSSBytes': reports[0]['processLifetimePeakRSSBytes'],
        'coldProcessLifetimePeakRSSBytes': [r['processLifetimePeakRSSBytes'] for r in reports[1:]],
        'memoryScope': reports[0]['memoryScope'], 'coldScope': reports[0]['coldScope'],
        'reports': [r['phase'] for r in reports]}
    if args.baseline_directory:
        baseline_dir = args.baseline_directory.resolve(strict=True)
        baseline = json.loads((baseline_dir / 'summary.json').read_text())
        same_fixture = json.loads((baseline_dir / 'fixture-pin.json').read_text()) == fixture_after
        gates = {name + 'P95Within10Percent': value['p95'] <= baseline['operationsMilliseconds'][name]['p95'] * 1.1
                 for name, value in metrics.items()}
        gates['warmProcessRSSWithin10Percent'] = receipt['warmProcessLifetimePeakRSSBytes'] <= baseline['warmProcessLifetimePeakRSSBytes'] * 1.1
        gates['coldProcessRSSWithin10Percent'] = stats(receipt['coldProcessLifetimePeakRSSBytes'])['p95'] <= stats(baseline['coldProcessLifetimePeakRSSBytes'])['p95'] * 1.1
        gates['exactFixture'] = same_fixture
        gates['geometryFeedbackHashes'] = baseline['geometryFeedbackHashes'] == hashes[0]
        gates['renderedPreviewPixels'] = baseline['renderedPreviewPixelDigest'] == receipt['renderedPreviewPixelDigest']
        receipt['applicableGates'] = gates
    write_json(output / 'summary.json', receipt)
    print(json.dumps(receipt, indent=2, sort_keys=True))
    if not all((before == after, fixture_before == fixture_after, invariant)):
        return 2
    return 0 if all(receipt.get('applicableGates', {}).values()) else 3


if __name__ == '__main__':
    raise SystemExit(main())
