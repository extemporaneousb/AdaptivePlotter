import fcntl
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from contextlib import closing

from reconcile_catalogs import reconcile


class CatalogReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.a, self.b, self.out = [self.root / x for x in ('studio', 'plotter', 'union')]
        for root in (self.a, self.b):
            root.mkdir()
            (root / 'library-writer.lock').touch()
            (root / 'drawing-authority.json').write_text('{"version":1,"catalog":"drawing-library.sqlite"}')
            db = sqlite3.connect(root / 'drawing-library.sqlite')
            db.executescript('''PRAGMA user_version=12;
              CREATE TABLE state(key TEXT PRIMARY KEY,value TEXT);
              INSERT INTO state VALUES('revision','1');
              CREATE TABLE dx_object(digest TEXT PRIMARY KEY,byte_length TEXT);
              CREATE TABLE dx_record(kind TEXT,namespace TEXT,identity TEXT,digest TEXT,PRIMARY KEY(kind,namespace,identity));
              CREATE TABLE dx_transaction(id TEXT PRIMARY KEY,index_digest TEXT,package_digest TEXT,intent TEXT);
              CREATE TABLE dx_tx_file(transaction_id TEXT,path TEXT,digest TEXT,PRIMARY KEY(transaction_id,path));
              CREATE TABLE dx_metadata(kind TEXT,namespace TEXT,identity TEXT,digest TEXT,payload TEXT,tombstoned INTEGER,PRIMARY KEY(kind,namespace,identity));
              CREATE TABLE dx_photo_metadata(namespace TEXT,identity TEXT,digest TEXT,payload TEXT,PRIMARY KEY(namespace,identity));
              CREATE TABLE domain_record(kind TEXT,id TEXT,payload TEXT,PRIMARY KEY(kind,id));''')
            db.close()

    def tearDown(self):
        self.temp.cleanup()

    def insert(self, root, table, row):
        with closing(sqlite3.connect(root / 'drawing-library.sqlite')) as db, db:
            db.execute('INSERT INTO ' + table + ' VALUES(' + ','.join('?' for _ in row) + ')', row)

    def test_union_keeps_authoritative_clears_tombstones_and_all_domain_rows(self):
        for root, title, reasons in [(self.a, None, ['chosen']), (self.b, 'Old label', ['plot-handoff'])]:
            self.insert(root, 'dx_record', ('drawing', 'ns', 'd', 'hash'))
            self.insert(root, 'dx_metadata', ('drawing', 'ns', 'd', 'hash', json.dumps(dict(title=title, retentionReasons=reasons, tombstoned=root == self.a)), int(root == self.a)))
            self.insert(root, 'dx_photo_metadata', ('ns', 'p', 'hash', json.dumps(dict(title=title, subjectID=title, sessionID=title, excluded=False))))
        self.insert(self.a, 'domain_record', ('flow', 'one', '{"value":1}'))
        self.insert(self.b, 'domain_record', ('attempt', 'two', '{"value":2}'))
        original = (self.a / 'drawing-library.sqlite').read_bytes()
        receipt = reconcile(self.a, self.b, self.out)
        with closing(sqlite3.connect(self.out / 'drawing-library.sqlite')) as db:
            metadata = json.loads(db.execute('SELECT payload FROM dx_metadata').fetchone()[0])
            self.assertIsNone(metadata['title'])
            self.assertTrue(metadata['tombstoned'])
            self.assertEqual(metadata['retentionReasons'], ['chosen', 'plot-handoff'])
            self.assertIsNone(json.loads(db.execute('SELECT payload FROM dx_photo_metadata').fetchone()[0])['subjectID'])
            self.assertEqual(db.execute('SELECT count(*) FROM domain_record').fetchone()[0], 2)
        self.assertEqual((self.a / 'drawing-library.sqlite').read_bytes(), original)
        self.assertEqual(len(receipt['metadataConflicts']), 2)

    def test_rejects_divergent_immutable_or_domain_identity_without_output(self):
        for table, first, second in [('dx_record', ('drawing', 'ns', 'd', 'one'), ('drawing', 'ns', 'd', 'two')),
                                      ('domain_record', ('flow', 'd', '{"v":1}'), ('flow', 'd', '{"v":2}'))]:
            self.insert(self.a, table, first)
            self.insert(self.b, table, second)
            with self.assertRaisesRegex(ValueError, 'Divergent'):
                reconcile(self.a, self.b, self.out)
            self.assertFalse(self.out.exists())
            for root in (self.a, self.b):
                with closing(sqlite3.connect(root / 'drawing-library.sqlite')) as db, db:
                    db.execute('DELETE FROM ' + table)

    def test_rejects_corrupt_cas_and_active_writer(self):
        value = b'original bytes'
        digest = hashlib.sha256(value).hexdigest()
        self.insert(self.a, 'dx_object', (digest, str(len(value))))
        with self.assertRaisesRegex(ValueError, 'CAS integrity'):
            reconcile(self.a, self.b, self.out)
        target = self.a / 'objects/sha256' / digest
        target.parent.mkdir(parents=True)
        target.write_bytes(value)
        with (self.b / 'library-writer.lock').open('rb') as lease:
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                reconcile(self.a, self.b, self.out)
        self.assertFalse(self.out.exists())

    def test_rejects_overwrite_of_either_input_or_existing_output(self):
        for output in (self.a, self.b, self.a / 'nested'):
            with self.assertRaises(ValueError):
                reconcile(self.a, self.b, output)


if __name__ == '__main__':
    unittest.main()
