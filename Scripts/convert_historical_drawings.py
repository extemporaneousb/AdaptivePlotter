#!/usr/bin/env python3
"""Convert a personal Portrait Library and Flow portfolio to a new Drawing Library."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import sqlite3
import struct
import subprocess
import tempfile
import uuid
import zlib
from collections import defaultdict
from contextlib import closing


# Stable namespace for the old single-user SQLite catalog, which had no issuer.
CATALOG = 'c443aee3-fe37-5638-a609-9387035198cf'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def packed(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def encoded(data):
    return base64.b64encode(data).decode('ascii')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def checked(data, expected):
    require(digest(data) == expected, f'Byte digest mismatch: {expected}')
    return data


def blob(folder, sha, suffix=''):
    require(re.fullmatch('[0-9a-f]{64}', sha), 'Invalid object address')
    path = folder / (sha + suffix)
    require(path.resolve().parent == folder.resolve(), f'Object outside {folder}')
    return {'path': str(path), 'sha256': sha}


def read_blob(folder, sha, suffix=''):
    return checked(Path(blob(folder, sha, suffix)['path']).read_bytes(), sha)


def field_bytes(data, field):
    """Slice the original top-level JSON member without re-encoding its doubles."""
    source = data.decode()
    decoder = json.JSONDecoder()
    pos = source.index('{') + 1
    while pos < len(source):
        pos += len(source[pos:]) - len(source[pos:].lstrip())
        name, pos = decoder.raw_decode(source, pos)
        pos = source.index(':', pos) + 1
        pos += len(source[pos:]) - len(source[pos:].lstrip())
        _, end = decoder.raw_decode(source, pos)
        if name == field:
            return source[pos:end].encode()
        pos = end
        while source[pos].isspace():
            pos += 1
        if source[pos] != ',':
            break
        pos += 1
    raise ValueError(f'Missing {field}')


def hex_hash(value):
    return bytes(value['bytes']).hex()


def db_open(root):
    db = sqlite3.connect((root / 'library-v1.sqlite').as_uri() + '?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    db.execute('BEGIN')
    return db


def photo_key(issuer, photo_id):
    return f'{issuer.lower()}/{photo_id.lower()}'


class Conversion:
    def __init__(self, stream, args):
        self.stream = stream
        self.args = args
        self.photos = {}
        self.photo_versions = {}
        self.drawings = set()
        self.requested = set(args.drawing)
        self.report = {'runs': {}, 'unresolved': [], 'sourceCatalogs': [], 'drawings': {}}

    def emit(self, **value):
        self.stream.write(packed(value) + b'\n')

    def photo(self, issuer, photo_id, asset, title, facts, acquired=None, session=None):
        key = photo_key(issuer, photo_id)
        if key in self.photos:
            require(self.photos[key] == asset['sha256'], f'Conflicting source occurrence {key}')
            return key
        self.photos[key] = asset['sha256']
        version = str(uuid.uuid5(uuid.UUID(issuer), key + digest(packed(facts)) + asset['sha256']))
        self.photo_versions[key] = version
        self.emit(key=key, source=dict(issuer=issuer, id=version, image=asset, title=title,
                  facts=encoded(packed(facts)), acquired=acquired, session=session))
        return key

    def catalog_photos(self, root, db):
        self.report['sourceCatalogs'].append(str(root))
        for row in db.execute('SELECT * FROM photo WHERE deleted=0 ORDER BY id'):
            facts = json.loads(row['reference'])
            require(facts['id'].lower() == row['id'] and facts['sourceSHA256'] == row['source_hash'],
                    'Photo row and reference disagree')
            self.photo(CATALOG, row['id'], blob(root / 'assets', row['source_hash']),
                       facts.get('label') or 'Photo', facts,
                       facts.get('capturedAt') if facts.get('captureTimeKnown') else None,
                       facts.get('captureSessionID'))

    def drawing(self, key, issuer, photo, program, expected, raster, created, title, facts, runs):
        require(key not in self.drawings and photo in self.photos, f'Duplicate drawing or missing photo: {key}')
        self.drawings.add(key)
        self.requested.discard(key)
        require(hex_hash(json.loads(program)['contentHash']) == expected, f'Wrong program for {key}')
        receipt = dict(legacyID=key, originalProgramSHA256=digest(program), programHash=expected,
                       photo=photo, photoRevision=self.photo_versions[photo], sourceSHA256=self.photos[photo],
                       provenance=facts, historicalRuns=sorted(runs, key=lambda item: item['runID']))
        revision = str(uuid.uuid5(uuid.UUID(issuer), digest(packed(receipt))))
        input_id = str(uuid.uuid5(uuid.UUID(issuer), 'input/' + revision))
        self.emit(key=key, artwork=dict(id=revision, inputID=input_id, issuer=issuer, photo=photo, program=encoded(program),
                  programHash=expected, raster=raster, created=created, title=title, receipt=encoded(packed(receipt))))
        self.report['drawings'][key] = dict(photo=photo, title=title, programHash=expected,
                                             runs=[r['runID'] for r in runs])
        self.report['runs'].update({r['runID']: r for r in runs})


def read_portfolio(root):
    head = json.loads((root / 'portfolio.json').read_bytes())
    require(head['schemaVersion'] in (1, 2), 'Unsupported portfolio head')
    cursor = head['recordSHA256']
    expected = head['revision']
    sources, candidates, prune_batches = {}, {}, []
    while cursor:
        record = json.loads(read_blob(root / 'records', cursor))
        require(record['schemaVersion'] == 1 and record['sequence'] == expected
                and record['portfolioID'] == head['portfolioID'], 'Broken portfolio chain')
        prune_batches.append(record['delta'].get('pruneRevisions', []))
        # Newest source/candidate upsert wins.
        for name, target in [('sources', sources), ('candidates', candidates)]:
            for item in record['delta'].get(name, []):
                target.setdefault(item['id'], item)
        cursor = record.get('previousRecordSHA256')
        expected -= 1
    require(expected == -1, 'Incomplete portfolio chain')
    prunes = replay_masks((edit for batch in reversed(prune_batches) for edit in batch), candidates)
    return head['portfolioID'], sources, candidates, prunes


def replay_masks(edits, candidates):
    """Flow deltas omitted the resulting masks. Replay their original stroke indices."""
    revisions, heads = {}, {}
    for edit in edits:
        key, candidate, action = edit['id'], edit['candidateID'], edit['action']
        previous, mask, undo, redo = heads.get(candidate, (None, set(), [], []))
        require(key not in revisions and edit.get('parentRevisionID') == previous, 'Broken pruning ancestry')
        indices = set(edit['affectedIndices'])
        require(sorted(indices) == edit['affectedIndices']
                and all(0 <= i < candidates[candidate]['strokeCount'] for i in indices), 'Invalid pruning indices')
        if action in ('remove', 'restore'):
            require(indices and (indices.isdisjoint(mask) if action == 'remove' else indices <= mask), 'Invalid stroke edit')
            (mask.update if action == 'remove' else mask.difference_update)(indices)
            undo.append(key)
            redo.clear()
        elif action in ('modelProposal', 'inheritedSelection'):
            require(previous is None, 'Initial mask has a prior revision')
            mask = indices.copy()
        elif action in ('undo', 'redo'):
            take, put = (undo, redo) if action == 'undo' else (redo, undo)
            require(take and take[-1] == edit['operationID'], 'Invalid pruning operation order')
            target = revisions[take.pop()]
            require(target['affectedIndices'] == edit['affectedIndices'], 'Pruning operation indices changed')
            remove = (target['action'] == 'remove') == (action == 'redo')
            (mask.update if remove else mask.difference_update)(indices)
            put.append(target['id'])
        else:
            require(action == 'completeTarget' and not indices, 'Unknown pruning operation')
        # The retired delta writer compacted derived state to missing/empty
        # arrays. Replay those placeholders; a nonempty recorded fact must agree.
        for field, expected in [('removedIndices', sorted(mask)), ('undoOperationIDs', undo),
                                ('redoOperationIDs', redo)]:
            recorded = edit.get(field)
            require(recorded is None or isinstance(recorded, list), f'Invalid archived pruning {field}')
            require(not recorded or recorded == expected, f'Contradictory archived pruning {field}')
        revisions[key] = dict(edit, removedIndices=sorted(mask),
                              undoOperationIDs=list(undo), redoOperationIDs=list(redo))
        heads[candidate] = key, mask, undo, redo
    return revisions


def portfolio(plan, root, binary):
    issuer, sources, candidates, prunes = read_portfolio(root)
    objects = root / 'objects'
    for src in sources.values():
        capture = src.get('captureProvenance', {})
        plan.photo(issuer, src['id'], blob(objects, src['image']['sha256']), src['title'],
                   src, capture.get('capturedAt'), src.get('sessionID'))
    for key, item in candidates.items():
        if plan.args.all_drawings or key in plan.requested:
            program = read_blob(objects, item['program']['sha256'])
            plan.drawing(key, issuer, photo_key(issuer, item['sourceID']), program, item['programHash'],
                         blob(objects, item['raster']['sha256']), item['createdAt'],
                         item.get('title') or sources[item['sourceID']]['title'] + ' · Flow Edge', item, [])
    plan.report['portfolioCandidateCount'] = len(candidates)
    plan.report['portfolioPruneCount'] = len(prunes)
    for key, prune in prunes.items():
        if not (plan.args.all_drawings or key in plan.requested):
            continue
        item = candidates[prune['candidateID']]
        version = 'flow-artist-v2' if item['recipe'].get('marks') is not None else 'flow-artist-v1'
        request = dict(base=blob(objects, item['program']['sha256']), expected=item['programHash'], revision=key,
                       removed=prune['removedIndices'], source=f"{version}|portfolio={issuer}|candidate={item['id']}|revision={key}")
        program = subprocess.check_output([binary, '--flow-prune'], input=packed(request))
        if not program:
            plan.requested.discard(key)
            plan.report.setdefault('emptyPruneRevisions', []).append(key)
            continue
        plan.drawing(key, issuer, photo_key(issuer, item['sourceID']), program, hex_hash(json.loads(program)['contentHash']),
                     blob(objects, item['raster']['sha256']), prune['createdAt'], sources[item['sourceID']]['title'] + ' · Flow Edge edit',
                     dict(candidate=item, pruning=prune, reconstructedFrom='archived stroke membership'), [])


def archive_runs(index_path):
    envelope = json.loads(index_path.read_bytes())
    index = json.loads(checked(base64.b64decode(envelope['payload'], validate=True), envelope['payloadSHA256']))
    folder = index_path.with_name(index_path.name + '.records')
    runs = defaultdict(dict)
    for key, kind in [('records', 'terminal'), ('attempts', 'attempt')]:
        for item in index[key]:
            data = json.loads(read_blob(folder, item['sha256'], '.json'))
            identity = data if kind == 'terminal' else data['intent']
            run = identity['runID']['rawValue'].lower()
            expected_id = identity['recordID']['rawValue'] if kind == 'terminal' else run
            require(expected_id.lower() == item['id'].lower() and kind not in runs[run], 'Duplicate or wrong raw identity')
            # Retain small binding facts; original full records and media live in the archive copy.
            entry = runs[run]
            attempt = data if kind == 'attempt' else data.get('attemptEvidence', {})
            candidate = attempt.get('intent', {}).get('context', {}).get('candidate')
            if candidate:
                signature = (candidate['candidateID'], hex_hash(candidate['programContentHash']), candidate.get('origin'))
                if 'candidate' in entry:
                    require(signature == entry['candidate'], f'Conflicting raw candidate for {run}')
                entry['candidate'] = signature
            entry[kind + 'SHA256'] = item['sha256']
            if kind == 'terminal':
                entry.update(frontiers=data['executionFrontiers'], status=next(iter(data['executionDisposition'])),
                             recordID=expected_id.lower(), executedProgram=hex_hash(data['program']['contentHash']))
            if 'inkDispatchPossible' in attempt:
                entry['dispatchPossible'] = attempt['inkDispatchPossible']
    for note in index.get('noInkConfirmations', []):
        runs[note['runID']['rawValue'].lower()]['noInkConfirmation'] = note
    return index['archiveID'], runs


def run_facts(archive, run, raw, method):
    return dict(archiveID=archive, runID=run, binding=method,
                **{k: v for k, v in raw.items() if k != 'candidate'})


def catalog(plan, root, db, archive, raw):
    bindings = defaultdict(list)
    priority = {row[0] for row in db.execute('SELECT DISTINCT drawing_id FROM work WHERE executed=1 AND deleted=0')}
    for row in db.execute('SELECT w.*, d.candidate_id,d.source_hash,d.program_hash FROM work w '
                          'JOIN drawing d ON w.drawing_id=d.id WHERE w.deleted=0 AND d.deleted=0'):
        run = row['run_id']
        entry = raw.get(run, {})
        method = json.loads(row['payload'])['recoveryMethod']
        if not (row['drawing_id'] in priority or plan.args.all_drawings or row['drawing_id'] in plan.requested):
            continue
        require(row['record_id'] == entry.get('recordID') and entry, f'Missing raw binding for {run}')
        candidate = entry.get('candidate', ())
        exact = candidate[:2] == (row['candidate_id'], row['program_hash'])
        if not exact:
            proof = db.execute('SELECT * FROM lineage_receipt WHERE run_id=?', (run,)).fetchone()
            exact = (proof and proof['drawing_id'] == row['drawing_id'] and proof['source_hash'] == row['source_hash']
                     and proof['program_hash'] == row['program_hash'] and proof['record_hash'] == entry.get('terminalSHA256')
                     and method == proof['method'] + ':' + proof['audit_hash'])
        if not exact:
            plan.report['unresolved'].append(dict(runID=run, reason='Candidate/lineage proof unavailable'))
            continue
        bindings[row['drawing_id']].append(run_facts(archive, run, entry, method))
    for row in db.execute('SELECT * FROM drawing WHERE deleted=0 ORDER BY id'):
        key = row['id']
        if not (bindings.get(key) or plan.args.all_drawings or key in plan.requested):
            continue
        record_hash = row['candidate_record'] or row['historical_record']
        data = read_blob(root / 'records', record_hash)
        record = json.loads(data)
        identity = record.get('identity', record)
        photo = photo_key(CATALOG, row['photo_id'])
        require(identity['photoID'].lower() == row['photo_id']
                and identity.get('candidateID', identity.get('id')) == row['candidate_id']
                and record['sourceSHA256'] == row['source_hash'] == plan.photos[photo]
                and record.get('rasterSHA256') == row['raster_hash'], 'Catalog drawing disagrees with archived record')
        plan.drawing(key, CATALOG, photo, field_bytes(data, 'program'), row['program_hash'],
                     blob(root / 'assets', row['raster_hash']) if row['raster_hash'] else None,
                     json.loads(row['summary'])['createdAt'], json.loads(row['summary'])['title'],
                     dict(recordSHA256=record_hash, **{k: v for k, v in record.items() if k != 'program'}), bindings[key])
    plan.report['catalogDrawingCount'] = db.execute('SELECT COUNT(*) FROM drawing WHERE deleted=0').fetchone()[0]
    plan.report['unresolved'] += [dict(runID=r[0], reason=r[1]) for r in db.execute('SELECT id,reason FROM quarantine')]


def transfer(plan, data, scratch, archive, raw, legacy_id=None):
    package = json.loads(data)
    origin = package['origin']
    issuer = origin['libraryID']
    key = 'transfer/' + issuer.lower() + '/' + origin['resultID'].lower()
    expected = hex_hash(origin['programHash'])
    result = json.loads(checked(base64.b64decode(package['resultRecordJSON'], validate=True), origin['resultRecordSHA256']))
    require(package['schemaVersion'] == 1, 'Unsupported historical transfer schema')
    if 'candidate' in result:
        require(result['portfolioID'] == issuer and result['candidate']['sourceID'] == origin['captureID']
                and (result.get('prune') or result['candidate'])['id'].lower() == origin['resultID'].lower()
                and result['candidate']['raster']['sha256'] == package['artistInput']['sha256'],
                'Transferred result origin disagrees with source')
    elif 'baseOrigin' in result:
        base = json.loads(base64.b64decode(result['originalPackageJSON'], validate=True))
        require(base['origin']['libraryID'] == issuer and result['baseOrigin']['captureID'] == origin['captureID']
                and base['origin']['captureID'] == origin['captureID']
                and base['source'] == package['source'] and base['artistInput'] == package['artistInput']
                and result['editID'].lower() == origin['resultID'].lower(), 'Edited transfer source mismatch')
        removed = {stroke['rawValue'] for stroke in result['removedStrokeIDs']}
        original = base['program']['strokes']
        initial = {s['rawValue'] for s in result['initialRemovedStrokeIDs']}
        kept = [s for s in original if s['id']['rawValue'] not in removed]
        require(result['baseProgram']['contentHash'] == result['baseOrigin']['programHash']
                and result['baseProgram']['strokes'] == [s for s in original if s['id']['rawValue'] not in initial]
                and kept == package['program']['strokes'],
                'Edited transfer geometry differs from recorded membership')
    else:
        require(result['id'] == origin['resultID'] and result['photoID'] == origin['captureID']
                and result['program'] == package['program'] and result['sourceSHA256'] == package['source']['sha256']
                and result['rasterSHA256'] == package['artistInput']['sha256'], 'Portrait candidate transfer mismatch')
    def unpack(name):
        obj = package[name]
        contents = checked(base64.b64decode(obj['bytes'], validate=True), obj['sha256'])
        f = scratch / obj['sha256']
        f.write_bytes(contents)
        return blob(scratch, obj['sha256'])
    photo = plan.photo(issuer, origin['captureID'], unpack('source'), package['title'], {'origin': origin})
    matches = [run_facts(archive, run, item, 'transferred candidate and origin')
               for run, item in raw.items() if item.get('candidate') == (legacy_id, expected, origin)]
    if key in plan.drawings:
        prior = plan.report['drawings'][key]
        require(prior['programHash'] == expected and prior['photo'] == photo, f'Conflicting transfer {key}')
        return
    plan.drawing(key, issuer, photo, field_bytes(data, 'program'), expected, unpack('artistInput'),
                 package['createdAt'], package['title'], dict(origin=origin, artist=package['artist']), matches)


def frame_png(frame, pixels):
    """Encode the camera's original RGB channels, stripping row padding and unused alpha."""
    width, height, stride = frame['width'], frame['height'], frame['rowBytes']
    fmt = frame['pixelFormat']
    require(fmt in ('gray8', 'rgba8', 'bgra8'), 'Unsupported retained frame format')
    channels = 1 if fmt == 'gray8' else 4
    require(0 < width <= 16384 and 0 < height <= 16384 and stride >= width * channels
            and len(pixels) == height * stride, 'Invalid camera frame dimensions')
    rows = bytearray()
    for y in range(height):
        row = pixels[y * stride:y * stride + width * channels]
        rows.append(0)  # PNG scanline filter, none.
        if channels == 1:
            rows.extend(row)
        else:
            rgb = bytearray(width * 3)
            order = (2, 1, 0) if fmt == 'bgra8' else (0, 1, 2)
            for dest, src in enumerate(order):
                rgb[dest::3] = row[src::4]
            rows.extend(rgb)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    header = struct.pack('>IIBBBBB', width, height, 8, 0 if channels == 1 else 2, 0, 0, 0)
    return bytes.fromhex('89504e470d0a1a0a') + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(rows, 3)) + chunk(b'IEND', b'')


def export_plot_photos(stage, runs):
    evidence = stage / 'DrawingEvidence'
    records = evidence / 'drawing-run-evidence-v1.json.records'
    media = evidence / 'drawing-run-evidence-v1.json.media'
    photos = {}
    for run, facts in runs.items():
        if 'terminalSHA256' not in facts:
            continue
        record = json.loads(read_blob(records, facts['terminalSHA256'], '.json'))
        for item in record.get('attemptEvidence', {}).get('terminalFrames', []):
            if 'live' not in item['source']:
                continue
            frame = item['frame']
            sha = frame['frameSHA256']
            path = Path('Plot Photographs') / str(uuid.UUID(run)) / (sha + '.png')
            pixels = read_blob(media, sha, '.pixels')
            require(len(pixels) == item['byteCount'], 'Camera frame byte count mismatch')
            (stage / path).parent.mkdir(parents=True, exist_ok=True)
            png = frame_png(frame, pixels)
            (stage / path).write_bytes(png)
            photos.setdefault(run, []).append(dict(path=str(path), frameSHA256=sha, pngSHA256=digest(png),
                                                    mediaReference=item))
    return photos


def convert(args, stage, scratch, binary):
    raw_root = args.evidence
    archive_copy = stage / 'DrawingEvidence'
    shutil.copytree(raw_root, archive_copy)
    archive, raw = archive_runs(archive_copy / 'drawing-run-evidence-v1.json')
    # Raw media files are addressed by their exact pixel digest.
    for pixels in (archive_copy / 'drawing-run-evidence-v1.json.media').glob('*.pixels'):
        checked(pixels.read_bytes(), pixels.stem)
    items = scratch / 'entries.jsonl'
    with items.open('wb') as stream, closing(db_open(args.catalog)) as db:
        plan = Conversion(stream, args)
        plan.catalog_photos(args.catalog, db)
        for root in args.photo_library:
            with closing(db_open(root)) as photos:
                plan.catalog_photos(root, photos)
        if args.portfolio:
            portfolio(plan, args.portfolio, binary)
        catalog(plan, args.catalog, db, archive, raw)
        for row in db.execute('SELECT id,reference FROM generic_drawing ORDER BY id'):
            record = read_blob(args.catalog / 'records', json.loads(row['reference'])['recordSHA256'])
            if 'transferredPackage' in json.loads(record):
                require(json.loads(record)['id'] == row['id'], 'Transferred catalog identity mismatch')
                transfer(plan, field_bytes(record, 'transferredPackage'), scratch, archive, raw, row['id'])
        for path in args.package:
            transfer(plan, path.read_bytes(), scratch, archive, raw)
        require(not plan.requested, f'Unknown drawing IDs: {plan.requested}')
    references = scratch / 'refs.json'
    subprocess.run([binary, stage / 'DrawingLibrary', items, references], check=True)
    report = plan.report
    report['plotPhotographs'] = export_plot_photos(stage, report['runs'])
    report.update(references=json.loads(references.read_bytes()), photoOccurrences=len(plan.photos),
                  distinctPhotoImages=len(set(plan.photos.values())), archiveID=archive,
                  rawArchive='DrawingEvidence', rawRunCount=len(raw))
    (stage / 'conversion.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(f'{len(plan.photos)} photos, {len(plan.drawings)} drawings, {len(report["runs"])} linked runs', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path, help='New directory for the Library, evidence copy and crosswalk')
    support = Path.home() / 'Library/Application Support/AdaptivePlotter'
    parser.add_argument('--catalog', type=Path, default=support / 'PortraitLibrary')
    parser.add_argument('--evidence', type=Path, default=support / 'DrawingEvidence')
    parser.add_argument('--portfolio', type=Path, help='Optional .flowportfolio directory')
    parser.add_argument('--photo-library', type=Path, action='append', default=[], help='Additional catalog, photos only')
    parser.add_argument('--package', type=Path, action='append', default=[], help='Additional Flow .portraitdrawing.json')
    parser.add_argument('--drawing', action='append', default=[], help='Also retain this catalog drawing ID or Flow candidate/pruning UUID')
    parser.add_argument('--all-drawings', action='store_true', help='Also convert unplotted catalog drawings and Flow candidates and pruning revisions')
    parser.add_argument('--scratch-path', type=Path, help='Reuse an existing SwiftPM build directory')
    args = parser.parse_args()
    args.destination = args.destination.resolve()
    for field in ('catalog', 'evidence', 'portfolio'):
        if getattr(args, field):
            setattr(args, field, getattr(args, field).resolve())
    args.photo_library = [p.resolve() for p in args.photo_library]
    inputs = [p for p in (args.catalog, args.evidence, args.portfolio, *args.photo_library) if p]
    require(not args.destination.exists() and all(p not in args.destination.parents for p in inputs),
            'Choose a new destination outside the source archives')
    repo = Path(__file__).resolve().parents[1]
    build = ['swift', 'build', '--package-path', repo, '-c', 'release']
    if args.scratch_path:
        build += ['--scratch-path', args.scratch_path.resolve()]
    subprocess.run([*build, '--product', 'HistoricalDrawingImport'], check=True)
    binaries = subprocess.check_output([*build, '--show-bin-path'], text=True).strip()
    with tempfile.TemporaryDirectory(dir=args.destination.parent) as staging, tempfile.TemporaryDirectory() as temp:
        stage = Path(staging) / 'converted'
        stage.mkdir(mode=0o700)
        convert(args, stage, Path(temp), Path(binaries) / 'HistoricalDrawingImport')
        require(not args.destination.exists(), 'Destination appeared during conversion')
        stage.rename(args.destination)


if __name__ == '__main__':
    main()
