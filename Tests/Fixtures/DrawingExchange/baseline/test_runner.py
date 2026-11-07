"""Fast negative controls for evidence freshness; no app, device or real corpus."""
import importlib.util
import json
import os
import pathlib
import tempfile
import types
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location('dx01_runner', pathlib.Path(__file__).with_name('run.py'))
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)

class RunnerControls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='adaptiveplotter-dx01-runner-', dir='/tmp')
        self.root = pathlib.Path(self.temp.name)
        self.args = types.SimpleNamespace(root=self.root, label=None)
        self.env = {'DX_BASELINE_ROOT':str(self.root/'catalog'), 'DX_BASELINE_PHOTOS':'40',
                    'DX_BASELINE_OPERATION':'photo-first-page', 'DX_BASELINE_TRIALS':'1'}
    def tearDown(self): self.temp.cleanup()
    def test_old_receipt_is_immutable_and_refused_before_launch(self):
        path=self.root/'receipts'/'same.json'; path.parent.mkdir(); old=b'{"old":true}\n'; path.write_bytes(old)
        with mock.patch.object(RUNNER.subprocess,'Popen') as launch:
            with self.assertRaisesRegex(RuntimeError,'existing run artifact'):
                RUNNER.invoke(self.args,'same',self.env,'NoMatchingDX01Tests',1)
            launch.assert_not_called()
        self.assertEqual(path.read_bytes(),old)
    def test_exit_zero_without_new_output_cannot_use_old_sibling(self):
        old=self.root/'receipts'/'old.json'; old.parent.mkdir(); old.write_bytes(b'{"old":true}')
        process=types.SimpleNamespace(wait=lambda timeout:0)
        with mock.patch.object(RUNNER.subprocess,'Popen',return_value=process):
            with self.assertRaisesRegex(RuntimeError,'no NEW measurement'):
                RUNNER.invoke(self.args,'new',self.env,'NoMatchingDX01Tests',1)
        self.assertEqual(old.read_bytes(),b'{"old":true}')
        self.assertFalse(json.loads((old.parent/'new.process.json').read_text())['measurementAccepted'])
    def test_inherited_dx_inputs_are_removed_and_identity_is_validated(self):
        captured={}
        def launch(command, **kwargs):
            captured.update(kwargs['env'])
            pathlib.Path(kwargs['env']['DX_BASELINE_OUTPUT']).write_text(json.dumps({
                'photos':40,'measurements':[{'operation':'wrong-operation','milliseconds':[1]}]}))
            return types.SimpleNamespace(wait=lambda timeout:0)
        with mock.patch.dict(os.environ, {'DX_UNEXPECTED_INHERITED':'must-not-reach-child'}), mock.patch.object(RUNNER.subprocess,'Popen',side_effect=launch):
            with self.assertRaisesRegex(RuntimeError,'operation identity mismatch'):
                RUNNER.invoke(self.args,'wrong',self.env,'DrawingExchangeBaselineTests',1)
        self.assertNotIn('DX_UNEXPECTED_INHERITED',captured)
        self.assertEqual(captured['DX_BASELINE_OPERATION'],'photo-first-page')
    def test_flow_requires_exactly_one_new_matching_receipt(self):
        def launch(command, **kwargs):
            for n in range(2):
                (self.root/f'flow-rename-{n}.json').write_text(json.dumps({'operation':'rename','samples':[]}))
            return types.SimpleNamespace(wait=lambda timeout:0)
        env={'DX_FLOW_ROOT':str(self.root),'DX_FLOW_PHASE':'measure','DX_FLOW_OPERATION':'rename','DX_FLOW_WARM_TRIALS':'0'}
        with mock.patch.object(RUNNER.subprocess,'Popen',side_effect=launch):
            with self.assertRaisesRegex(RuntimeError,'exactly one NEW'):
                RUNNER.invoke(self.args,'duplicate-flow',env,'DrawingExchangeFlowBaselineTests',1)
    def test_sample_count_and_not_applicable_are_constrained(self):
        with self.assertRaisesRegex(RuntimeError,'sample count'):
            RUNNER.validate_measurement({'photos':40,'measurements':[{'operation':'photo-first-page','milliseconds':[]}]},self.env)
        with self.assertRaisesRegex(RuntimeError,'invalid not-applicable'):
            RUNNER.validate_measurement({'photos':40,'status':'not_applicable','pageSize':100,'trials':0},self.env)

if __name__=='__main__': unittest.main()
