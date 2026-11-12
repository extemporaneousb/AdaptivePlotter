#!/usr/bin/env python3
"""Offline personal catalog union. Always writes a new directory; never installs it."""
import argparse
import hashlib
import fcntl
import json
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def semantic(row):
    """SQLite JSON text order is not a conflicting authored identity."""
    def value(item):
        if isinstance(item, str) and item.startswith(('{', '[')):
            try:
                return json.loads(item)
            except ValueError:
                pass
        return item
    return tuple(value(item) for item in row)


def verify(db, root):
    require(db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok', 'Catalog integrity failed')
    require(not db.execute('PRAGMA foreign_key_check').fetchall(), 'Dangling catalog references')
    for digest, length in db.execute('SELECT digest,byte_length FROM dx_object'):
        require(len(digest) == 64 and all(c in '0123456789abcdef' for c in digest), 'Bad CAS address')
        path = root / 'objects/sha256' / digest
        require(path.is_file() and not path.is_symlink() and path.stat().st_size == int(length)
                and sha(path) == digest, f'CAS integrity failed: {digest}')
    for tx, index, expected in db.execute('SELECT id,index_digest,package_digest FROM dx_transaction'):
        entries = list(db.execute('SELECT f.path,f.digest,o.byte_length FROM dx_tx_file f '
                                 'JOIN dx_object o ON f.digest=o.digest WHERE transaction_id=? ORDER BY f.path', (tx,)))
        inventory = ''.join(f'{p}\0{d}\0{n}\n' for p, d, n in entries).encode()
        require(hashlib.sha256(inventory).hexdigest() == expected, f'Publication inventory failed: {tx}')
        require(any(p == 'data/exchange.json' and d == index for p, d, _ in entries), 'Missing publication index')


def reconcile(authoritative, received, output):
    authoritative, received, output = [Path(p).resolve() for p in (authoritative, received, output)]
    require(not output.exists(), 'Output must not exist')
    require(not any(output == p or p in output.parents or output in p.parents for p in (authoritative, received)),
            'Output must be separate from both source libraries')
    output.parent.mkdir(parents=True, exist_ok=True)
    partial = Path(tempfile.mkdtemp(prefix='.' + output.name + '-', dir=output.parent))
    receipt = {'profile': 'adaptiveplotter.personal-catalog-reconciliation/1',
               'authoritative': str(authoritative), 'received': str(received), 'added': {}, 'metadataConflicts': []}
    leases, connections = [], []
    try:
        for root in (authoritative, received):
            lock = os.open(root / 'library-writer.lock', os.O_RDONLY | os.O_NOFOLLOW)
            leases.append(lock)
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        sources = []
        snapshots = partial / 'source-snapshots'
        snapshots.mkdir()
        for label, root in [('authoritative', authoritative), ('received', received)]:
            require((root / 'drawing-authority.json').is_file(), 'Missing authority marker')
            source = sqlite3.connect((root / 'drawing-library.sqlite').as_uri() + '?mode=ro', uri=True)
            connections.append(source)
            target = sqlite3.connect(snapshots / (label + '.sqlite'))
            connections.append(target)
            with source, target:
                source.backup(target)
            source.close()
            require(target.execute('PRAGMA user_version').fetchone()[0] == 12, 'Only current schema 12 is supported')
            verify(target, root)
            sources.append(target)
            receipt[label + 'SnapshotSHA256'] = sha(snapshots / (label + '.sqlite'))
        dest = sqlite3.connect(partial / 'drawing-library.sqlite')
        connections.append(dest)
        sources[0].backup(dest)
        dest.execute('PRAGMA foreign_keys=OFF')
        schema = lambda db: dict(db.execute("SELECT name,sql FROM sqlite_master WHERE type='table'"))
        require(schema(sources[0]) == schema(sources[1]), 'Catalog schemas differ')
        with dest:
            for table in schema(dest):
                if table == 'state':
                    continue  # Studio retains catalog UUID and neutral metadata revision authority.
                columns = list(dest.execute('PRAGMA table_info(' + quote(table) + ')'))
                keys = [c[0] for c in sorted(columns, key=lambda c: c[5]) if c[5]]
                require(keys, 'Table has no primary key: ' + table)
                rows = {tuple(row[i] for i in keys): row for row in dest.execute('SELECT * FROM ' + quote(table))}
                added = 0
                for row in sources[1].execute('SELECT * FROM ' + quote(table)):
                    key = tuple(row[i] for i in keys)
                    if key in rows:
                        if semantic(rows[key]) != semantic(row):
                            require(table in ('dx_metadata', 'dx_photo_metadata'), f'Divergent {table} identity: {key}')
                            # Both values survive in immutable source snapshots and this explicit receipt.
                            receipt['metadataConflicts'].append({'table': table, 'key': key,
                                                                 'selected': rows[key], 'received': row})
                            names = [c[1] for c in columns]
                            digest_index, payload_index = names.index('digest'), names.index('payload')
                            require(rows[key][digest_index] == row[digest_index], 'Divergent metadata exact reference')
                            base, other = [json.loads(r[payload_index]) for r in (rows[key], row)]
                            if table == 'dx_metadata':
                                base['retentionReasons'] = list(dict.fromkeys(base.get('retentionReasons', []) + other.get('retentionReasons', [])))
                            where = ' AND '.join(quote(names[i]) + '=?' for i in keys)
                            dest.execute('UPDATE ' + quote(table) + ' SET payload=? WHERE ' + where,
                                         (json.dumps(base, separators=(',', ':')), *key))
                        continue
                    dest.execute('INSERT INTO ' + quote(table) + ' VALUES(' + ','.join('?' for _ in row) + ')', row)
                    added += 1
                receipt['added'][table] = added
            revisions = [int(db.execute("SELECT value FROM state WHERE key='revision'").fetchone()[0]) for db in sources]
            dest.execute("UPDATE state SET value=? WHERE key='revision'", (str(max(revisions) + 1),))
        for db, root in zip(sources, (authoritative, received)):
            for digest, _ in db.execute('SELECT digest,byte_length FROM dx_object'):
                target = partial / 'objects/sha256' / digest
                if not target.exists():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(root / 'objects/sha256' / digest, target)
        shutil.copyfile(authoritative / 'drawing-authority.json', partial / 'drawing-authority.json')
        verify(dest, partial)
        receipt['counts'] = dict(dest.execute('SELECT kind,count(*) FROM dx_record GROUP BY kind'))
        receipt['domainRecords'] = dest.execute('SELECT count(*) FROM domain_record').fetchone()[0]
        dest.close()
        for source in sources:
            source.close()
        (partial / 'reconciliation.json').write_text(json.dumps(receipt, indent=2) + '\n')
        partial.rename(output)
        return receipt
    except BaseException:
        shutil.rmtree(partial)
        raise
    finally:
        for connection in connections:
            connection.close()
        for lock in leases:
            os.close(lock)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--authoritative', required=True, type=Path)
    parser.add_argument('--received', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(reconcile(args.authoritative, args.received, args.output), indent=2))
