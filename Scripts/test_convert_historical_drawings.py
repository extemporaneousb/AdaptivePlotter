import base64
import json
from pathlib import Path
import tempfile
import zlib
import unittest

from convert_historical_drawings import archive_runs, digest, field_bytes, frame_png, packed, read_portfolio, replay_masks


class HistoricalDrawingTests(unittest.TestCase):
    def test_original_program_bytes_survive_nested_decoys(self):
        program = b'{"strokes":[1.2300,1e-9], "name":"a}b"}'
        archive = b'{"nested":{"program":0},"program":' + program + b',"footer":false}'
        self.assertEqual(field_bytes(archive, 'program'), program)

    def test_no_ink_confirmation_does_not_replace_commanded_frontier(self):
        with tempfile.TemporaryDirectory() as temp:
            index = Path(temp) / 'raw.json'
            records = Path(temp) / 'raw.json.records'
            records.mkdir()
            run = 'ABC'
            terminal = packed(dict(runID={'rawValue': run}, recordID={'rawValue': 'DEF'},
                                   executionDisposition={'cancelled': {}}, program={'contentHash': {'bytes': [0] * 32}},
                                   executionFrontiers={'commandedStrokeCount': 9, 'inkVerifiedStrokeCount': 0}))
            sha = digest(terminal)
            (records / (sha + '.json')).write_bytes(terminal)
            confirmation = dict(runID={'rawValue': run}, recordedAt=1)
            manifest = packed(dict(archiveID='archive', attempts=[], records=[dict(id='DEF', sha256=sha)],
                                   noInkConfirmations=[confirmation]))
            index.write_bytes(packed(dict(payload=base64.b64encode(manifest).decode(), payloadSHA256=digest(manifest))))
            _, runs = archive_runs(index)
            self.assertEqual(runs['abc']['noInkConfirmation'], confirmation)
            self.assertEqual(runs['abc']['frontiers'], {'commandedStrokeCount': 9, 'inkVerifiedStrokeCount': 0})
            (records / (sha + '.json')).write_bytes(b'{}')
            with self.assertRaisesRegex(ValueError, 'digest mismatch'):
                archive_runs(index)

    def test_compact_remove_undo_and_redo_recover_original_membership(self):
        def operation(key, action, parent, target=None):
            return dict(id=key, action=action, parentRevisionID=parent, candidateID='drawing',
                        operationID=target, affectedIndices=[1], removedIndices=[])
        edits = [operation('a', 'remove', None), operation('b', 'undo', 'a', 'a'),
                 operation('c', 'redo', 'b', 'a')]
        prunes = replay_masks(edits, {'drawing': {'strokeCount': 3}})
        self.assertEqual([e['removedIndices'] for e in prunes.values()], [[1], [], [1]])
        edits[2]['operationID'] = 'different'
        with self.assertRaisesRegex(ValueError, 'operation order'):
            replay_masks(edits, {'drawing': {'strokeCount': 3}})

    def test_plot_photo_preserves_rgb_channels_with_padded_rows(self):
        raw = bytes([3, 2, 1, 0, 45, 45, 6, 5, 4, 255, 55, 55])
        png = frame_png(dict(width=1, height=2, rowBytes=6, pixelFormat='bgra8'), raw)
        begin = png.index(b'IDAT') + 4
        length = int.from_bytes(png[begin-8:begin-4], 'big')
        self.assertEqual(zlib.decompress(png[begin:begin+length]), bytes([0, 1, 2, 3, 0, 4, 5, 6]))

    def test_incomplete_portfolio_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'records').mkdir()
            data = packed(dict(schemaVersion=1, portfolioID='one', sequence=1, delta={'sources': [], 'candidates': []}))
            (root / 'records' / digest(data)).write_bytes(data)
            (root / 'portfolio.json').write_text(json.dumps(dict(schemaVersion=2, portfolioID='one', revision=1,
                                                                 recordSHA256=digest(data))))
            with self.assertRaisesRegex(ValueError, 'Incomplete portfolio'):
                read_portfolio(root)


if __name__ == '__main__':
    unittest.main()
