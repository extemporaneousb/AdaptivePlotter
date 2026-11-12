#!/usr/bin/env python3
"""Prepare verified personal Flow history for HistoricalDrawingImport --flow-learning.

Inputs remain read-only. The native importer accepts an existing OFFLINE library,
never selects or replaces a running application's catalog.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('historical_converter', ROOT / 'Scripts/convert_historical_drawings.py')
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


def prepare(archive, references=None):
    archive = Path(archive).resolve()
    head_bytes = (archive / 'portfolio.json').read_bytes()
    head = json.loads(head_bytes)
    require = converter.require
    cursor, sequence = head['recordSHA256'], head['revision']
    chain = []
    while cursor:
        raw = converter.read_blob(archive / 'records', cursor)
        record = json.loads(raw)
        require(record['schemaVersion'] == 1 and record['sequence'] == sequence
                and record['portfolioID'] == head['portfolioID'], 'Broken Flow history chain')
        chain.append((cursor, record))
        cursor = record.get('previousRecordSHA256')
        sequence -= 1
    require(sequence == -1, 'Incomplete Flow history')
    tables = {key: {} for key in ('sources', 'rounds', 'candidates', 'choices', 'pruneRevisions',
                                  'presentations', 'rankings', 'trainingSnapshots', 'fits', 'activations', 'legacyImports')}
    selection = {}
    for _, record in reversed(chain):
        for key, values in record['delta'].items():
            if key in tables:
                for value in values:
                    tables[key][value['id']] = value
            else:
                selection[key] = values
    prunes = converter.replay_masks(tables['pruneRevisions'].values(), tables['candidates'])
    snapshot = dict(schemaVersion=2, purpose=chain[-1][1]['portfolioPurpose'], id=head['portfolioID'],
                    createdAt=chain[-1][1]['portfolioCreatedAt'], revision=head['revision'],
                    **{k: list(v.values()) for k, v in tables.items() if k != 'legacyImports'}, **selection)
    snapshot['pruneRevisions'] = list(prunes.values())
    snapshot['activeFitID'] = None
    snapshot['activations'] = []
    # Old snapshots are preserved as historical provenance, never mislabeled as
    # newly frozen current-format tasks or implicitly activated checkpoints.
    snapshot['trainingSnapshots'] = []
    snapshot['fits'] = []
    refs = (references or {}).get('references', references or {})
    for source in snapshot['sources']:
        photo = refs.get('photos', {}).get(converter.photo_key(head['portfolioID'], source['id']))
        if photo:
            source['photo'] = photo
    for candidate in snapshot['candidates']:
        drawing = refs.get('drawings', {}).get(candidate['id'])
        if drawing:
            candidate['drawing'] = drawing
    artifacts = []
    # Validate every retained object, including all intermediate programs, old
    # training documents, report and checkpoint bytes before writing output.
    for path in sorted((archive / 'objects').iterdir()):
        converter.checked(path.read_bytes(), path.name)
        artifacts.append(dict(path=str(path), sha256=path.name))
    for digest, _ in chain:
        artifacts.append(dict(path=str(archive / 'records' / digest), sha256=digest))
    artifacts.append(dict(path=str(archive / 'portfolio.json'), sha256=hashlib.sha256(head_bytes).hexdigest()))
    historical = {k: list(tables[k].values()) for k in ('trainingSnapshots', 'fits', 'activations', 'legacyImports')}
    repairs = {field: sum(not original.get(field) and bool(prunes[key][field])
                           for key, original in tables['pruneRevisions'].items())
               for field in ('removedIndices', 'undoOperationIDs', 'redoOperationIDs')}
    return dict(profile='adaptiveplotter.personal-flow-recovery/1', snapshot=snapshot,
                replayRepairRule='Missing/empty derived masks and undo/redo stacks in the retired compact delta format are replayed from original operations; nonempty contradictory recorded state is rejected. Original journal bytes remain unchanged.',
                replayRepairs=repairs,
                head=head, artifacts=artifacts, historical=historical,
                candidates=[dict(id=x['id'], program=x['program'], raster=x['raster'], preview=x['preview'])
                            for x in snapshot['candidates']],
                counts={k: len(v) for k, v in tables.items()})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--references', type=Path)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--importer', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    require = converter.require
    library = args.library.resolve()
    for live in ('PortraitStudio', 'AdaptivePlotter'):
        forbidden = Path.home() / 'Library/Application Support' / live
        require(forbidden not in library.parents, 'Use an offline library copy; live catalogs are not accepted')
    plan = prepare(args.archive, json.loads(args.references.read_bytes()) if args.references else None)
    with tempfile.TemporaryDirectory(prefix='flow-recovery-') as temp:
        manifest = Path(temp) / 'plan.json'
        manifest.write_bytes(converter.packed(plan))
        subprocess.run([str(args.importer.resolve()), '--flow-learning', str(library), str(manifest),
                        str(args.receipt.resolve())], check=True)
        receipt = json.loads(args.receipt.read_bytes())
        receipt.update(replayRepairRule=plan['replayRepairRule'], replayRepairs=plan['replayRepairs'])
        args.receipt.write_text(json.dumps(receipt, indent=2) + '\n')
