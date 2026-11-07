"""Fast driver acceptance controls; no Swift, LLVM, benchmark or device execution."""
import importlib.util
import json
import shlex
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('dx01_coverage', Path(__file__).with_name('coverage.py'))
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)


class CoverageAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='dx01-acceptance-negative-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.args = SimpleNamespace(scratch=self.root, name='selected', control='noop',
            flow_operation=None, operation=None, transfer=None, archive=False, corpus=None, photos=None,
            archive_records=None, archive_interrupted=None)
        self.meta = {'binary': '/mock/instrumented-tests', 'binarySHA256': 'binary-sha'}
        helper = self.root / 'swiftpm-testing-helper'
        helper.write_bytes(b'mocked executable helper')
        helper.chmod(0o700)
        self.helper_command = [str(helper), '--test-bundle-path', self.meta['binary'],
            '--scratch-path', str(self.root / 'build'), '--filter', 'ObservedSuite',
            self.meta['binary'], '--testing-library', 'swift-testing']
        proof_profile = self.root / 'diagnostic-direct-2.profraw'
        proof_profile.write_bytes(b'capability profile excluded from admitted profiles')
        coverage.write(self.root / 'direct-helper-diagnostic.json', {'command': self.helper_command,
            'helperPID': 2, 'exitCode': 0, 'profiles': [str(proof_profile)], 'exactPIDProfilePresent': True,
            'measurementPresent': True, 'helperSHA256': coverage.sha(helper)})
        coverage.write(self.root / 'helper-invocation-observation.json', {'swiftPMPID': 1, 'exitCode': 0,
            'observedHelpers': [{'pid': 2, 'parentPID': 1, 'command': shlex.join(self.helper_command)}]})

    def accepted_fixture(self, control='noop'):
        directory = self.root / self.args.name
        (directory / 'profiles').mkdir(parents=True)
        (directory / 'profiles' / 'test-7301.profraw').write_bytes(b'profile')
        receipt = {'control': control, 'expectedOwnerEntries': 0}
        if control == 'program-decode':
            receipt.update(expectedDrawingProgramDecodeEntries=1, programContentHash='a' * 64)
        coverage.write(directory / 'measurement.json', receipt)
        command, launcher = coverage.launcher_command(self.args, self.meta, 'SelectedSuite')
        record = {'command': command, 'launcher': launcher, 'acceptance': 'accepted', 'pid': 7301, 'exitCode': 0, 'binarySHA256': 'binary-sha',
            'measurementTrials': 1, 'scope': 'mock control process', 'environment': {'DX_COUNTER_CONTROL': control}}
        record.update(coverage.validate_run(directory, record, self.meta, require_accepted=False))
        coverage.write(directory / 'run.json', record)
        return directory

    def mocked_export(self, counts):
        return [patch.object(coverage, 'verified_build', return_value=self.meta),
            patch.object(coverage.subprocess, 'run'),
            patch.object(coverage.subprocess, 'check_output', return_value=json.dumps(
                {'type': 'llvm.coverage.json.export', 'version': '2.0.1'}).encode()),
            patch.object(coverage, 'mappings', return_value=counts),
            patch.object(coverage, 'checkpoint_region', return_value={'availability': 'unavailable'})]

    def test_zero_matching_test_run_cannot_be_exported(self):
        args = self.args
        class EmptySuccessfulRunner:
            pid = 7301
            def __init__(self, *unused, **kwargs):
                pattern = kwargs['env']['LLVM_PROFILE_FILE']
                Path(pattern.replace('%p', str(self.pid))).write_bytes(b'profile without test receipt')
            def wait(self):
                return 0
        with patch.object(coverage, 'verified_build', return_value=self.meta), \
             patch.object(coverage.subprocess, 'check_output') as no_help, \
             patch.object(coverage.subprocess, 'Popen', EmptySuccessfulRunner):
            with self.assertRaises(FileNotFoundError):
                coverage.run(args)
            no_help.assert_not_called()
        directory = self.root / args.name
        self.assertNotEqual(json.loads((directory / 'run.json').read_text())['acceptance'], 'accepted')
        self.assertTrue((directory / 'run.rejected.json').exists())
        with patch.object(coverage, 'verified_build', return_value=self.meta), \
             patch.object(coverage.subprocess, 'run') as llvm:
            with self.assertRaisesRegex(RuntimeError, 'acceptance not established'):
                coverage.export(args)
            llvm.assert_not_called()
        self.assertFalse((directory / 'structural.json').exists())
        self.assertTrue((directory / 'export.rejected.json').exists())

    def test_preexisting_measurement_or_profile_prevents_any_process_launch(self):
        original = coverage.launcher_command
        for artifact in ('measurement', 'profile'):
            with self.subTest(artifact=artifact):
                self.args.name = artifact
                def contaminated(args, meta, selected):
                    command, launcher = original(args, meta, selected)
                    directory = args.scratch / args.name
                    if artifact == 'measurement':
                        coverage.write(directory / 'measurement.json', {'control': 'noop', 'expectedOwnerEntries': 0})
                    else:
                        (directory / 'profiles' / 'test-7301.profraw').write_bytes(b'stale preflight profile')
                    return command, launcher
                with patch.object(coverage, 'verified_build', return_value=self.meta), \
                     patch.object(coverage, 'launcher_command', side_effect=contaminated), \
                     patch.object(coverage.subprocess, 'Popen') as process, \
                     patch.object(coverage.subprocess, 'check_output') as help_process:
                    with self.assertRaisesRegex(RuntimeError, 'artifacts exist before'):
                        coverage.run(self.args)
                    process.assert_not_called()
                    help_process.assert_not_called()
                directory = self.root / artifact
                self.assertNotEqual(json.loads((directory / 'run.json').read_text())['acceptance'], 'accepted')
                self.assertTrue((directory / 'run.rejected.json').exists())

    def test_failed_controls_never_publish_accepted_structure(self):
        for control, count in [('noop', 1), ('program-decode', 0)]:
            with self.subTest(control=control):
                self.args.name = control
                directory = self.accepted_fixture(control)
                patches = self.mocked_export({'DrawingProgram.init(from': {'functionEntryCount': count}})
                with patches[0], patches[1], patches[2], patches[3], patches[4]:
                    with self.assertRaises(RuntimeError):
                        coverage.export(self.args)
                self.assertFalse((directory / 'structural.json').exists())
                self.assertEqual(json.loads((directory / 'export.rejected.json').read_text())['acceptance'], 'rejected')
                # A rejected attempt cannot be retried into an accepted artifact.
                with self.assertRaises(FileExistsError):
                    coverage.export(self.args)
                self.assertFalse((directory / 'structural.json').exists())

    def test_receipt_changed_after_acceptance_is_rejected(self):
        directory = self.accepted_fixture()
        coverage.write(directory / 'measurement.json', {'control': 'noop', 'expectedOwnerEntries': 0, 'changed': True})
        with patch.object(coverage, 'verified_build', return_value=self.meta), \
             patch.object(coverage.subprocess, 'run') as llvm:
            with self.assertRaisesRegex(RuntimeError, 'receipt/profile changed'):
                coverage.export(self.args)
            llvm.assert_not_called()
        self.assertFalse((directory / 'structural.json').exists())

    def test_other_pid_profile_or_modified_profile_cannot_be_exported(self):
        for mutation in ('extra-pid', 'changed-content'):
            with self.subTest(mutation=mutation):
                self.args.name = mutation
                directory = self.accepted_fixture()
                if mutation == 'extra-pid':
                    (directory / 'profiles' / 'test-9999.profraw').write_bytes(b'foreign process')
                else:
                    (directory / 'profiles' / 'test-7301.profraw').write_bytes(b'changed')
                with patch.object(coverage, 'verified_build', return_value=self.meta), \
                     patch.object(coverage.subprocess, 'run') as llvm:
                    with self.assertRaises(RuntimeError):
                        coverage.export(self.args)
                    llvm.assert_not_called()
                self.assertFalse((directory / 'structural.json').exists())

    def test_receipt_wrong_identity_or_condition_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'control receipt identity'):
            coverage.validate_receipt({'control': 'db-positive'}, {'DX_COUNTER_CONTROL': 'noop'})
        with self.assertRaisesRegex(RuntimeError, 'condition/trials'):
            coverage.validate_receipt({'photos': 40, 'trials': 1},
                {'DX_BASELINE_TRIALS': '1', 'DX_BASELINE_ROOT': '/mock', 'DX_BASELINE_PHOTOS': '1000', 'DX_BASELINE_OPERATION': 'photo-first-page'})
        with self.assertRaisesRegex(RuntimeError, 'identity'):
            coverage.validate_receipt({'photos': 40, 'trials': 1, 'phase': 'read', 'operationFilter': 'photo-first-page',
                'measurements': [{'operation': 'drawing-first-page', 'milliseconds': [1]}]},
                {'DX_BASELINE_TRIALS': '1', 'DX_BASELINE_ROOT': '/mock', 'DX_BASELINE_PHOTOS': '40', 'DX_BASELINE_OPERATION': 'photo-first-page'})

    def test_helper_observation_rejects_wrong_bundle_or_parent(self):
        evidence = self.root / 'helper-invocation-observation.json'
        original = json.loads(evidence.read_text())
        for kind in ('bundle', 'parent'):
            with self.subTest(kind=kind):
                changed = json.loads(json.dumps(original))
                if kind == 'bundle':
                    changed['observedHelpers'][0]['command'] = shlex.join([
                        '/wrong/bundle' if word == self.meta['binary'] else word for word in self.helper_command])
                else:
                    changed['observedHelpers'][0]['parentPID'] = 999
                coverage.write(evidence, changed)
                with self.assertRaises(RuntimeError):
                    coverage.launcher_command(self.args, self.meta, 'SelectedSuite')
        coverage.write(evidence, original)

    def test_toolchain_drift_requires_new_direct_helper_proof(self):
        (self.root / 'swiftpm-testing-helper').write_bytes(b'changed since capability diagnostic')
        with self.assertRaisesRegex(RuntimeError, 'proof/binary/PID profile identity mismatch'):
            coverage.launcher_command(self.args, self.meta, 'SelectedSuite')

    def test_accepted_helper_changed_cannot_export(self):
        directory = self.accepted_fixture()
        (self.root / 'swiftpm-testing-helper').write_bytes(b'changed executable')
        with patch.object(coverage, 'verified_build', return_value=self.meta), \
             patch.object(coverage.subprocess, 'run') as llvm:
            with self.assertRaisesRegex(RuntimeError, 'helper/observation identity changed'):
                coverage.export(self.args)
            llvm.assert_not_called()
        self.assertFalse((directory / 'structural.json').exists())

    def test_archive_valid_receipt_and_rejected_count_digest_trials(self):
        root = self.root / 'frozen-archive'
        root.mkdir()
        (root / 'legacy.json').write_bytes(b'frozen fixture bytes, not a decoded program')
        digest = coverage.sha(root / 'legacy.json')
        coverage.write(root / 'selection.json', {'legacySHA256': digest})
        env = {'DX_ARCHIVE_ROOT': str(root), 'DX_ARCHIVE_RECORDS': '100', 'DX_ARCHIVE_INTERRUPTED': '10',
            'DX_ARCHIVE_EXPECTED_SHA256': digest, 'DX_BASELINE_TRIALS': '1'}
        receipt = {'phase': 'read', 'operation': 'legacy-loadSnapshot', 'legacyTerminalRecords': 100,
            'interruptedAttempts': 10, 'legacySHA256': digest, 'milliseconds': [1.25]}
        coverage.validate_receipt(receipt, env)
        for field, wrong in [('legacyTerminalRecords', 101), ('interruptedAttempts', 11),
                ('legacySHA256', '0' * 64), ('milliseconds', [1, 2]), ('operation', 'wrong')]:
            with self.subTest(field=field):
                with self.assertRaises(RuntimeError):
                    coverage.validate_receipt(dict(receipt, **{field: wrong}), env)
        # A mismatched tiny selector cannot authenticate even a matching receipt.
        coverage.write(root / 'selection.json', {'legacySHA256': '0' * 64})
        with self.assertRaisesRegex(RuntimeError, 'selection/legacy digest'):
            coverage.validate_receipt(receipt, env)

    def test_success_is_published_only_after_checks_and_never_overwritten(self):
        directory = self.accepted_fixture()
        patches = self.mocked_export({'DrawingProgram.init(from': {'functionEntryCount': 0}})
        with patches[0], patches[1], patches[2], patches[3], patches[4]:
            coverage.export(self.args)
        self.assertEqual(json.loads((directory / 'structural.json').read_text())['acceptance'], 'accepted')
        self.assertFalse((directory / 'export.rejected.json').exists())
        with self.assertRaisesRegex(RuntimeError, 'overwrite'):
            coverage.export(self.args)


if __name__ == '__main__':
    unittest.main()
