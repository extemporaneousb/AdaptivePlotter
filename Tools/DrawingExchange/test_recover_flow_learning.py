import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import uuid

from recover_flow_learning import prepare, converter


class FlowLearningRecoveryPlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'objects').mkdir()
        (self.root / 'records').mkdir()
        self.portfolio, self.source = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
        self.image = b'original encoded image bytes, separate from prepared pixels'
        self.image_digest = hashlib.sha256(self.image).hexdigest()
        (self.root / 'objects' / self.image_digest).write_bytes(self.image)
        self.base = dict(id=self.source, createdAt=12, title='Before', excluded=False,
                         image=dict(sha256=self.image_digest, byteCount=len(self.image), mediaType='image/png'))
        self.head = None

    def tearDown(self):
        self.temp.cleanup()

    def append(self, sequence, delta):
        record = dict(schemaVersion=1, sequence=sequence, portfolioID=self.portfolio,
                      portfolioPurpose='artist', portfolioCreatedAt=1,
                      previousRecordSHA256=self.head, delta=delta)
        raw = converter.packed(record)
        self.head = hashlib.sha256(raw).hexdigest()
        (self.root / 'records' / self.head).write_bytes(raw)
        (self.root / 'portfolio.json').write_bytes(converter.packed(dict(schemaVersion=2,
            portfolioID=self.portfolio, revision=sequence, recordSHA256=self.head)))

    def test_replay_preserves_original_choice_and_uses_exact_occurrence_mapping(self):
        choice = dict(id=str(uuid.uuid4()), createdAt=23, purpose='refine-or-prune', selectedItemID='selected')
        self.append(0, dict(sources=[self.base], choices=[choice]))
        changed = dict(self.base, title='After')
        old_fit = dict(id=str(uuid.uuid4()), snapshotID=str(uuid.uuid4()), report={'sha256': self.image_digest})
        self.append(1, dict(sources=[changed], fits=[old_fit]))
        exact = dict(issuer=self.portfolio.lower(), revision=str(uuid.uuid4()), digest='a' * 64)
        refs = {'references': {'photos': {converter.photo_key(self.portfolio, self.source): exact}}}
        before = {str(p): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        plan = prepare(self.root, refs)
        self.assertEqual(plan['snapshot']['sources'][0]['photo'], exact)
        self.assertEqual(plan['snapshot']['sources'][0]['title'], 'After')
        self.assertEqual(plan['snapshot']['choices'], [choice])
        self.assertEqual(plan['snapshot']['fits'], [])
        self.assertEqual(plan['historical']['fits'], [old_fit])
        self.assertEqual(plan['counts']['choices'], 1)
        self.assertEqual(len(plan['artifacts']), 4)
        self.assertEqual(before, {str(p): p.read_bytes() for p in self.root.rglob('*') if p.is_file()})

    def test_refuses_corrupted_chain_or_original_object(self):
        self.append(0, dict(sources=[self.base]))
        record = self.root / 'records' / self.head
        original = record.read_bytes()
        record.write_bytes(original + b' ')
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            prepare(self.root)
        record.write_bytes(original)
        (self.root / 'objects' / self.image_digest).write_bytes(b'prepared replacement')
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            prepare(self.root)


if __name__ == '__main__':
    unittest.main()
