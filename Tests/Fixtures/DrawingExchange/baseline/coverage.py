#!/usr/bin/env python3
"""DX01 separate structural pass. Explicit build/run/export phases; no latency claim.

Build only after the uninstrumented benchmark executor releases exclusivity:
  coverage.py --scratch /tmp/adaptiveplotter-dx01-coverage-UNIQUE build
Run one control or one operation per fresh process; export separately. See --help.
Never prepares/mutates corpora and never uses the ordinary .build directory.

Fresh-scratch helper capability procedure (diagnostics are never admitted counts):
1. After build, run the public SwiftPM command below with DX_COUNTER_CONTROL=noop,
   DX_BASELINE_OUTPUT=$scratch/diagnostic-noop.json and a unique LLVM_PROFILE_FILE:
   swift test --scratch-path "$scratch/build" --skip-build --enable-code-coverage
     --disable-xctest --enable-swift-testing --no-parallel
     --filter DrawingExchangeCounterControlsTests
   While it runs, capture its exact child command/PID/PPID with
   /bin/ps -axo pid=,ppid=,command=. Retain the actual parent Popen PID and exit.
2. Save helper-invocation-observation.json with {swiftPMPID, exitCode,
   observedHelpers:[{pid,parentPID,command}]} from that observation (one helper).
   Its --test-bundle-path and positional bundle must equal build.json's binary;
   --scratch-path must equal this scratch/build. Do not guess helper flags.
3. Replay that observed child argv directly, changing --filter to the
   counter-control suite, using DX_COUNTER_CONTROL=noop, a fresh diagnostic
   receipt, and LLVM_PROFILE_FILE=$scratch/diagnostic-direct-%p.profraw.
   Save direct-helper-diagnostic.json with {command:[argv...], helperPID,
   exitCode, profiles:[absolute emitted path], exactPIDProfilePresent:true,
   measurementPresent:true, helperSHA256:<SHA256 of command[0]>}. Require one
   nonempty profile ending -<helperPID>.profraw and the expected noop receipt.
   SwiftPM itself may override LLVM_PROFILE_FILE; its pooled profiles are excluded.
   Do not invoke helper --help: this toolchain executes the selected test instead
   of displaying parser help. Final runs have no test-executing preflight; use a
   new run name with absent measurement/profile artifacts before launch.
Canonical /tmp path aliases are resolved before replay. The driver binds both observations to the current helper SHA and exact loaded
bundle argv. Changed toolchains require fresh observations/proof; stale proof
cannot authorize a changed helper. --helper-observation/--helper-proof override
only receipt locations, not these identity checks.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import shlex
import subprocess
import sys
import tarfile

REPO = Path(__file__).resolve().parents[4]
OWNERS = {
    'Sources/PortraitLibrary/PortraitLibraryDatabase.swift':
        ('PortraitLibraryDatabase', ('rows', 'prepare', 'execute', 'decode', 'index', 'checkedDrawing', 'checkedPhoto')),
    'Sources/PortraitLibrary/PortraitCandidateStore.swift': ('PortraitCandidateStore', ('browseAsset', 'readAsset', 'browseRecord', 'readRecords')),
    'Sources/PortraitLibrary/PortraitLibraryQueries.swift': ('PortraitCandidateStore', ('librarySnapshot', 'loadDrawing')),
    'Sources/PlotterModel/DrawingProgram.swift': ('DrawingProgram', ('init(from',)),
    'Sources/PortraitStudioUI/FlowDojoModel.swift': ('FlowDojoModel', ('refresh',)),
    'Sources/PortraitStudioUI/FlowDojoRenderer.swift': ('FlowDojoRenderer', ('preview',)),
    'Sources/PortraitLibrary/FlowPortfolioStore.swift': ('FlowPortfolioStore', ('checkpointData', 'candidateProgram')),
    'Sources/PortraitLibrary/FlowPortfolioStorage.swift': ('FlowPortfolioStorage', ('read',)),
}
OPERATIONS = ('photo-first-page', 'photo-next-page', 'drawing-first-page',
              'drawing-next-page', 'photo-filtered-drawing-page', 'exact-drawing-load', 'large-drawing-load',
              'gallery-first-page', 'gallery-next-page', 'identity-drawing-load')


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def capture(argv):
    return subprocess.check_output(argv, cwd=REPO, text=True).strip()


def source_identity():
    # All compiled source inputs, not merely the selected instrumented owners.
    paths = [REPO / 'Package.swift'] + sorted((REPO / 'Sources').rglob('*.swift')) + sorted((REPO / 'Tests').rglob('*.swift'))
    return {str(p.relative_to(REPO)): sha(p) for p in paths}


def safe_scratch(path):
    path = Path(path).resolve()
    if not str(path).startswith('/private/tmp/adaptiveplotter-dx01-coverage-') and not str(path).startswith('/tmp/adaptiveplotter-dx01-coverage-'):
        raise RuntimeError('scratch must be a distinct /tmp/adaptiveplotter-dx01-coverage-* root')
    return path


def build(args):
    root = args.scratch
    root.mkdir(parents=True, exist_ok=False)
    command = ['swift', 'build', '--build-tests', '--enable-code-coverage', '--scratch-path', str(root / 'build'), '-c', 'debug']
    metadata = {'command': command, 'sourceIdentity': source_identity(),
        'gitHEAD': capture(['git', 'rev-parse', 'HEAD']),
        'gitStatus': capture(['git', 'status', '--short']),
        'swiftVersion': capture(['swift', '--version']),
        'sdkPath': capture(['xcrun', '--sdk', 'macosx', '--show-sdk-path']),
        'sdkVersion': capture(['xcrun', '--sdk', 'macosx', '--show-sdk-version']),
        'llvmProfdataVersion': capture(['xcrun', 'llvm-profdata', '--version']),
        'llvmCovVersion': capture(['xcrun', 'llvm-cov', '--version'])}
    write(root / 'build.json', metadata)
    with (root / 'build.log').open('wb') as log:
        subprocess.run(command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT, check=True)
    binaries = list((root / 'build').glob('**/*.xctest/Contents/MacOS/*'))
    binaries = [p for p in binaries if p.is_file() and os.access(p, os.X_OK)]
    if len(binaries) != 1:
        raise RuntimeError(f'expected exactly one test executable, found {binaries}')
    runners = list((root / 'build').glob('**/AdaptivePlotterPackageTests.derived/runner.swift'))
    if len(runners) != 1 or 'if argument == "--testing-library"' not in runners[0].read_text():
        raise RuntimeError('generated runner does not establish explicit testing-library dispatch')
    metadata.update(binary=str(binaries[0].resolve()), binarySHA256=sha(binaries[0]),
        generatedRunnerPath=str(runners[0]), generatedRunnerSHA256=sha(runners[0]))
    write(root / 'build.json', metadata)


def verified_build(root):
    meta = json.loads((root / 'build.json').read_text())
    if source_identity() != meta['sourceIdentity']:
        raise RuntimeError('source identity changed since instrumented build')
    if sha(Path(meta['binary'])) != meta['binarySHA256']:
        raise RuntimeError('instrumented binary changed')
    return meta



def flow_inventory(root):
    rows = []
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise RuntimeError('Flow seed contains symlink')
        if path.is_file():
            rows.append([str(path.relative_to(root)), path.stat().st_size, sha(path)])
    return hashlib.sha256(json.dumps(rows, separators=(',', ':')).encode()).hexdigest()


def install_flow_seed(root):
    # Flow test guard requires one immediate real /tmp child, so reuse the
    # coverage scratch root itself. The test copies this frozen seed before work.
    here = Path(__file__).resolve().parent
    seed = here / 'flow-seed.tar.gz'
    manifest = json.loads((here / 'flow-seed.manifest.json').read_text())
    if sha(seed) != manifest['seedSHA256']:
        raise RuntimeError('Flow seed archive digest mismatch')
    frozen = root / 'flow-frozen.flowportfolio'
    if not frozen.exists():
        frozen.mkdir()
        with tarfile.open(seed) as archive:
            seen = set()
            for member in archive.getmembers():
                path = Path(member.name)
                if not member.isfile() or path.is_absolute() or '..' in path.parts or member.name in seen:
                    raise RuntimeError('invalid/duplicate Flow seed archive member')
                seen.add(member.name)
                destination = frozen / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    raise RuntimeError('missing Flow seed payload')
                with source, destination.open('xb') as output:
                    shutil.copyfileobj(source, output)
                destination.chmod(0o444)
        # Payload files are read-only; keep directory modes copy-compatible.
        # The existing harness copies these modes to its writable work tree and
        # replaces the head atomically. Verify the original root after the run.
    if flow_inventory(frozen) != manifest['rootSHA256']:
        raise RuntimeError('Flow seed root digest mismatch')
    return frozen


def checkpoint_region(counts):
    relative = 'Sources/PortraitStudioUI/FlowDojoModel.swift'
    lines = (REPO / relative).read_text().splitlines()
    marker = 'activeCheckpoint = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: await store.checkpointData(fitID: fitID))'
    matches = [(i + 1, line) for i, line in enumerate(lines) if marker in line]
    if len(matches) != 1:
        raise RuntimeError('refresh checkpoint decode expression identity changed')
    line_number, line = matches[0]
    start = line.index('JSONDecoder().decode') + 1
    end = len(line) + 1
    candidates = []
    for function in counts['FlowDojoModel.refresh']['rawMappings']:
        file_ids = [i for i, path in enumerate(function['filenames']) if Path(path).resolve() == (REPO / relative).resolve()]
        for region in function['regions']:
            # Only a region on the actual expression line can supply a useful
            # callsite observation. Enclosing function/branch counts cannot.
            if region[5] in file_ids and region[7] == 0 and region[0] == region[2] == line_number and region[1] <= start and region[3] >= end:
                candidate = {'symbol': function['symbol'], 'region': region}
                if candidate not in candidates:
                    candidates.append(candidate)
    return {'availability': 'mapped' if len(candidates) == 1 else 'unavailable',
        'regionExecutionCount': candidates[0]['region'][4] if len(candidates) == 1 else None,
        'sourceFile': relative, 'line': line_number, 'expression': line[start - 1:],
        'rawMappings': candidates,
        'meaning': 'exact-line source region executions in refresh, not literal decoder entries or successful decodes; whole-process open/setup included; multiple mappings remain ambiguous; compare reopen/rename/rank separately without blind subtraction'}




def archive_digest(root):
    selected = json.loads((root / 'selection.json').read_text()).get('legacySHA256')
    if not re.fullmatch('[0-9a-f]{64}', str(selected)) or sha(root / 'legacy.json') != selected:
        raise RuntimeError('frozen archive selection/legacy digest mismatch')
    return selected


def validate_receipt(obj, env):
    """Require the selected harness result, not merely a zero-exit runner."""
    if not isinstance(obj, dict):
        raise RuntimeError('measurement receipt must be an object')
    control = env.get('DX_COUNTER_CONTROL')
    if control:
        if obj.get('control') != control:
            raise RuntimeError('control receipt identity mismatch')
        if control == 'noop' and obj.get('expectedOwnerEntries') != 0:
            raise RuntimeError('noop oracle missing')
        if control == 'program-decode' and (obj.get('expectedDrawingProgramDecodeEntries') != 1 or
                not re.fullmatch('[0-9a-f]{64}', str(obj.get('programContentHash', '')))):
            raise RuntimeError('program decode oracle missing')
        if control == 'db-positive' and any(obj.get(key) != value for key, value in
                [('expectedRowsEntries', 4), ('expectedPrepareEntries', 4), ('expectedExecuteEntries', 1)]):
            raise RuntimeError('DB positive oracle missing')
        return
    operation = env.get('DX_FLOW_OPERATION') or env.get('DX_BASELINE_OPERATION')
    if env.get('DX_FLOW_ROOT'):
        if env.get('DX_FLOW_WARM_TRIALS') != '0' or obj.get('operation') != operation or obj.get('phase') != 'measure' or obj.get('measuredWarmOperationCount') != 0:
            raise RuntimeError('Flow receipt identity/trials mismatch')
        wanted = 1 if operation == 'reopen' else 0
        if len(obj.get('samples', [])) != wanted or obj.get('initialOperationCount') != (0 if operation == 'reopen' else 1):
            raise RuntimeError('Flow first-operation receipt mismatch')
        frozen = Path(env['DX_FLOW_ROOT']) / 'flow-frozen.flowportfolio'
        manifest = json.loads((Path(__file__).resolve().parent / 'flow-seed.manifest.json').read_text())
        if flow_inventory(frozen) != manifest['rootSHA256'] or obj.get('baselineHeadSHA256') != sha(frozen / 'portfolio.json'):
            raise RuntimeError('Flow seed/head oracle mismatch')
        durations = [sample.get('seconds') for sample in obj.get('samples', [])] if operation == 'reopen' else [obj.get('firstOperationAfterOpenSeconds')]
        if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or v < 0 for v in durations):
            raise RuntimeError('Flow first-operation result missing/invalid')
        return
    if env.get('DX_BASELINE_TRIALS') != '1':
        raise RuntimeError('structural receipt requested trials must equal one')
    if env.get('DX_ARCHIVE_ROOT'):
        expected = archive_digest(Path(env['DX_ARCHIVE_ROOT']))
        if obj.get('phase') != 'read' or obj.get('operation') != 'legacy-loadSnapshot':
            raise RuntimeError('archive operation identity mismatch')
        if obj.get('legacyTerminalRecords') != int(env['DX_ARCHIVE_RECORDS']) or obj.get('interruptedAttempts') != int(env['DX_ARCHIVE_INTERRUPTED']):
            raise RuntimeError('archive terminal/interrupted count mismatch')
        if obj.get('legacySHA256') != expected or env.get('DX_ARCHIVE_EXPECTED_SHA256') != expected:
            raise RuntimeError('archive receipt/input digest mismatch')
        values = obj.get('milliseconds', [])
    elif env.get('DX_BASELINE_ROOT'):
        if obj.get('photos') != int(env['DX_BASELINE_PHOTOS']) or obj.get('trials') != 1:
            raise RuntimeError('catalog receipt condition/trials mismatch')
        if obj.get('status') == 'not_applicable':
            raise RuntimeError('not-applicable operation cannot produce accepted structural counts')
        if 'measurements' in obj:
            measurements = obj['measurements']
            if len(measurements) != 1 or measurements[0].get('operation') != operation or obj.get('operationFilter') != operation or obj.get('phase') != 'read':
                raise RuntimeError('catalog receipt identity mismatch')
            values = measurements[0].get('milliseconds', [])
        else:
            if obj.get('operation') != operation or obj.get('pageSize') != 100:
                raise RuntimeError('actor receipt identity mismatch')
            values = obj.get('milliseconds', [])
    else:
        if not env.get('DX_TRANSFER_ROOT') or obj.get('operation') != operation:
            raise RuntimeError('transfer receipt identity mismatch')
        if obj.get('inputPackageSHA256') != env['DX_TRANSFER_EXPECTED_PACKAGE_SHA256']:
            raise RuntimeError('transfer package oracle mismatch')
        manifest = json.loads((Path(__file__).resolve().parent / 'legacy-v1.manifest.json').read_text())
        if env['DX_TRANSFER_EXPECTED_PACKAGE_SHA256'] != manifest['packageSHA256'] or env['DX_TRANSFER_EXPECTED_PROGRAM_HASH'] != manifest['programHash']:
            raise RuntimeError('transfer expected oracle differs from checked manifest')
        if operation == 'v1-native-export' and (obj.get('actualExportOutput', {}).get('sha256') != manifest['packageSHA256'] or obj.get('exportOutputSHA256PerSample') != [manifest['packageSHA256']]):
            raise RuntimeError('native export output oracle mismatch')
        values = obj.get('milliseconds', [])
    if len(values) != 1 or any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or v < 0 for v in values):
        raise RuntimeError('receipt needs exactly one valid sample')


def validate_run(directory, record, meta, require_accepted=True):
    if require_accepted and record.get('acceptance') != 'accepted':
        raise RuntimeError('run acceptance not established')
    if record.get('exitCode') != 0 or record.get('binarySHA256') != meta['binarySHA256'] or record.get('measurementTrials') != 1:
        raise RuntimeError('run exit/build/trials identity mismatch')
    launcher = record.get('launcher', {})
    if launcher.get('loadedBundlePath') != meta['binary'] or launcher.get('loadedBundleSHA256') != meta['binarySHA256']:
        raise RuntimeError('loaded bundle identity not established')
    if sha(Path(launcher['helperPath'])) != launcher['helperSHA256'] or sha(Path(launcher['observationPath'])) != launcher['observationSHA256'] or sha(Path(launcher['proofPath'])) != launcher['proofSHA256']:
        raise RuntimeError('helper/observation identity changed')
    if not record.get('command') or record['command'][0] != launcher['helperPath']:
        raise RuntimeError('profile PID is not associated with observed bundle-loading helper')
    receipt = directory / 'measurement.json'
    validate_receipt(json.loads(receipt.read_text()), record['environment'])
    profiles = list((directory / 'profiles').glob('*'))
    expected = directory / 'profiles' / f'test-{record["pid"]}.profraw'
    if profiles != [expected] or not expected.stat().st_size:
        raise RuntimeError('profile process identity not established')
    hashes = {'measurementSHA256': sha(receipt), 'profileSHA256': sha(expected)}
    if require_accepted and any(record.get(key) != value for key, value in hashes.items()):
        raise RuntimeError('accepted receipt/profile changed')
    return hashes



def launcher_command(args, meta, test_filter):
    # macOS SwiftPM emits a Mach-O loadable bundle, not an executable. Replay
    # the actually observed SwiftPM child helper argv; never exec that bundle.
    evidence = getattr(args, 'helper_observation', None) or args.scratch / 'helper-invocation-observation.json'
    observed = json.loads(evidence.read_text())
    children = observed.get('observedHelpers', [])
    if observed.get('exitCode') != 0 or len(children) != 1 or children[0].get('parentPID') != observed.get('swiftPMPID'):
        raise RuntimeError('helper invocation observation has no successful unique child identity')
    # /tmp and /private/tmp are the same macOS filesystem identity. Preserve
    # the observed argv in the receipt and replay canonical path aliases.
    observed_command = shlex.split(children[0]['command'])
    command = [str(Path(word).resolve()) if word.startswith('/') else word for word in observed_command]
    if not command or Path(command[0]).name != 'swiftpm-testing-helper' or not Path(command[0]).is_absolute():
        raise RuntimeError('observation does not identify the installed SwiftPM testing helper')
    for flag, wanted in [('--test-bundle-path', meta['binary']),
                         ('--scratch-path', str(args.scratch / 'build')),
                         ('--testing-library', 'swift-testing')]:
        if command.count(flag) != 1 or command[command.index(flag) + 1] != wanted:
            raise RuntimeError('helper bundle/scratch/library identity mismatch')
    if command.count(meta['binary']) != 2 or command.count('--filter') != 1:
        raise RuntimeError('helper observation lacks exact loaded-bundle/filter mapping')
    command[command.index('--filter') + 1] = test_filter
    helper = Path(command[0])
    if not helper.is_file() or not os.access(helper, os.X_OK):
        raise RuntimeError('observed helper is unavailable')
    proof_path = getattr(args, 'helper_proof', None) or args.scratch / 'direct-helper-diagnostic.json'
    proof = json.loads(proof_path.read_text())
    proof_command = [str(Path(word).resolve()) if word.startswith('/') else word for word in proof.get('command', [])]
    if proof_command.count('--filter') != 1:
        raise RuntimeError('direct helper proof lacks selected filter')
    proof_command[proof_command.index('--filter') + 1] = test_filter
    proof_profiles = proof.get('profiles', [])
    if proof_command != command or proof.get('exitCode') != 0 or proof.get('helperSHA256') != sha(helper) or not proof.get('measurementPresent') or not proof.get('exactPIDProfilePresent') or len(proof_profiles) != 1 or not proof_profiles[0].endswith('-' + str(proof.get('helperPID')) + '.profraw') or not Path(proof_profiles[0]).is_file() or not Path(proof_profiles[0]).stat().st_size:
        raise RuntimeError('direct helper proof/binary/PID profile identity mismatch; observe current toolchain again')
    return command, {'observedCommand': observed_command, 'proofPath': str(proof_path), 'proofSHA256': sha(proof_path), 'helperPath': str(helper), 'helperSHA256': sha(helper),
        'observationPath': str(evidence), 'observationSHA256': sha(evidence),
        'loadedBundlePath': meta['binary'], 'loadedBundleSHA256': meta['binarySHA256']}


def run(args):
    meta = verified_build(args.scratch)
    directory = args.scratch / args.name
    directory.mkdir(exist_ok=False)
    profiles = directory / 'profiles'
    profiles.mkdir()
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(('DX_', 'LLVM_PROFILE_FILE')):
            del env[key]
    env.update(LLVM_PROFILE_FILE=str(profiles / 'test-%p.profraw'),
               DX_BASELINE_OUTPUT=str(directory / 'measurement.json'), DX_BASELINE_TRIALS='1')
    if args.control:
        env['DX_COUNTER_CONTROL'] = args.control
        if args.control == 'db-positive':
            if args.corpus is None:
                raise RuntimeError('db-positive requires --corpus')
            env['DX_COUNTER_DATABASE_ROOT'] = str(args.corpus)
        test_filter = 'DrawingExchangeCounterControlsTests'
    elif args.flow_operation:
        frozen = install_flow_seed(args.scratch)
        flow_before = set(args.scratch.glob('flow-*.json'))
        flow_identity = flow_inventory(frozen)
        env.update(DX_FLOW_ROOT=str(args.scratch), DX_FLOW_PHASE='measure',
            DX_FLOW_OPERATION=args.flow_operation, DX_FLOW_WARM_TRIALS='0')
        test_filter = 'DrawingExchangeFlowBaselineTests'
    elif args.archive:
        if args.corpus is None or args.archive_records is None or args.archive_interrupted is None:
            raise RuntimeError('archive requires --corpus, --archive-records and --archive-interrupted')
        expected_archive = archive_digest(args.corpus)
        env.update(DX_ARCHIVE_ROOT=str(args.corpus), DX_BASELINE_PHASE='read',
            DX_ARCHIVE_RECORDS=str(args.archive_records), DX_ARCHIVE_INTERRUPTED=str(args.archive_interrupted),
            DX_ARCHIVE_EXPECTED_SHA256=expected_archive)
        test_filter = 'DrawingExchangeArchiveBaselineTests.archive'
    elif args.operation:
        if args.corpus is None or args.photos is None:
            raise RuntimeError('catalog operation requires --corpus and explicit --photos')
        env.update(DX_BASELINE_ROOT=str(args.corpus), DX_BASELINE_PHASE='read',
            DX_BASELINE_OPERATION=args.operation, DX_BASELINE_PHOTOS=str(args.photos))
        test_filter = 'DrawingExchangeBaselineTests.catalog'
    else:
        if args.corpus is None:
            raise RuntimeError('transfer requires --corpus containing frozen legacy-v1.json')
        # Existing transfer harness creates disposable work directories under its
        # root. Stage only the frozen package, keeping the corpus read-only.
        transfer_manifest = json.loads((Path(__file__).resolve().parent / 'legacy-v1.manifest.json').read_text())
        if sha(args.corpus / 'legacy-v1.json') != transfer_manifest['packageSHA256']:
            raise RuntimeError('frozen transfer package differs from checked manifest')
        staged = directory / 'transfer-fixture'
        staged.mkdir()
        shutil.copyfile(args.corpus / 'legacy-v1.json', staged / 'legacy-v1.json')
        env.update(DX_TRANSFER_ROOT=str(staged), DX_BASELINE_PHASE='read', DX_BASELINE_OPERATION=args.transfer,
            DX_TRANSFER_EXPECTED_PROGRAM_HASH=transfer_manifest['programHash'],
            DX_TRANSFER_EXPECTED_PACKAGE_SHA256=transfer_manifest['packageSHA256'])
        test_filter = 'DrawingExchangeBaselineTests.transfer'
    command, launcher = launcher_command(args, meta, test_filter)
    # This installed helper forwards --help to a runner which executes tests.
    # Capability is established by observed argv/direct proof, never another
    # test invocation disguised as a help preflight.
    record = {'command': command, 'launcher': launcher, 'environment': {k: v for k, v in env.items() if k.startswith(('DX_', 'LLVM_PROFILE_FILE'))},
        'binarySHA256': meta['binarySHA256'], 'buildReceipt': str(args.scratch / 'build.json'),
        'scope': 'whole single selected test process; includes runner/setup/assertions; next-page includes first-page cursor setup; transfer includes package decode/import/save setup',
        'latencyClaim': False, 'measurementTrials': 1, 'acceptance': 'not_established'}
    if args.archive:
        record['scope'] = 'whole selected raw legacy-loadSnapshot test process including tiny selection read, archive decoding, media verification and post-operation checks; Python input digest verified before launch; n=1 no warmup; DrawingProgram owner entries are not total decoder calls; not native/physical evidence'
    if args.transfer:
        record['frozenTransferSource'] = str(args.corpus / 'legacy-v1.json')
        record['frozenTransferSHA256'] = sha(args.corpus / 'legacy-v1.json')
    if (directory / 'measurement.json').exists() or any(profiles.iterdir()):
        record['rejectionReason'] = 'measurement/profile artifacts exist before selected process launch'
        write(directory / 'run.json', record)
        write(directory / 'run.rejected.json', record)
        raise RuntimeError(record['rejectionReason'])
    with (directory / 'run.log').open('wb') as log:
        process = subprocess.Popen(command, cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT)
        record['pid'] = process.pid
        record['exitCode'] = process.wait()
    write(directory / 'run.json', record)
    try:
        if args.flow_operation:
            emitted = set(args.scratch.glob('flow-*.json')) - flow_before
            if len(emitted) != 1:
                record['flowReceiptError'] = 'expected exactly one Flow receipt'
            else:
                receipt = next(iter(emitted))
                observed = json.loads(receipt.read_text())
                if observed.get('operation') != args.flow_operation or observed.get('measuredWarmOperationCount') != 0:
                    raise RuntimeError('unexpected Flow operation/trials receipt')
                shutil.copyfile(receipt, directory / 'measurement.json')
                record['flowReceipt'] = str(receipt)
            if flow_inventory(frozen) != flow_identity:
                raise RuntimeError('instrumented Flow run mutated frozen seed')
            record['flowFrozenRootSHA256'] = flow_identity
            record['scope'] = 'whole single Flow test process including seed copy, model.open setup, one initial operation, assertions and shutdown; reopen is open only; generate uses synthetic render override; no operation-only or native frame claim'
        record.update(validate_run(directory, record, meta, require_accepted=False))
        record['acceptance'] = 'accepted'
        write(directory / 'run.json', record)
    except Exception as error:
        record['rejectionReason'] = str(error)
        write(directory / 'run.rejected.json', record)
        raise


def owner_targets():
    for relative, (owner, methods) in OWNERS.items():
        yield relative, owner, methods
    # One source file owns both the archive value decoder and the store API.
    yield 'Sources/PlotterRuntime/DrawingRunEvidenceStore.swift', 'DrawingRunEvidenceArchive', ('init(from',)
    yield 'Sources/PlotterRuntime/DrawingRunEvidenceStore.swift', 'DrawingRunEvidenceStore', ('loadSnapshot',)


def mappings(export):
    if export.get('type') != 'llvm.coverage.json.export' or not re.fullmatch(r'\d+\.\d+\.\d+', str(export.get('version', ''))):
        raise RuntimeError('unrecognized llvm-cov export schema')
    functions = []
    for unit in export['data']:
        functions.extend(unit['functions'])
    symbols = [f['name'] for f in functions]
    demangled = subprocess.run(['xcrun', 'swift-demangle', '--compact'], input='\n'.join(symbols) + '\n',
                              text=True, capture_output=True, check=True).stdout.splitlines()
    if len(demangled) != len(functions):
        raise RuntimeError('demangle did not preserve symbol cardinality')
    result = {}
    for relative, owner, methods in owner_targets():
        source = (REPO / relative).read_text().splitlines()
        for method in methods:
            key = owner + '.' + method
            identity_overload = relative == 'Sources/PortraitLibrary/PortraitLibraryQueries.swift' and method == 'loadDrawing'
            if identity_overload:
                key = owner + '.loadDrawing(identity)'
            entries = []
            for f, name in zip(functions, demangled):
                if any(token in name for token in ('closure #', 'thunk', 'default argument', 'implicit closure')):
                    continue
                if method == 'init(from':
                    matched = owner + '.init(from:' in name
                else:
                    # Swift demangles private names as (name in _HASH), and
                    # generic specializations put <...> before the argument list.
                    pattern = re.escape(owner) + r'\.(?:' + re.escape(method) + r'|\(' + re.escape(method) + r' in [^)]+\))(?:<.*>)?\('
                    matched = re.search(pattern, name) is not None
                if not matched or (identity_overload and 'PortraitDrawingIdentity' not in name):
                    continue
                filenames = f['filenames']
                owner_ids = [i for i, p in enumerate(filenames) if Path(p).resolve() == (REPO / relative).resolve()]
                if not owner_ids:
                    continue
                regions = f['regions']
                if any(not isinstance(r, list) or len(r) != 8 or not all(isinstance(v, int) for v in r) for r in regions):
                    raise RuntimeError('unrecognized LLVM region shape')
                owner_regions = [r for r in regions if r[5] in owner_ids and r[7] == 0]
                if not owner_regions:
                    raise RuntimeError(f'no code region for {name}')
                if method == 'init(from' and owner == 'DrawingProgram':
                    # Exact DrawingProgram decoder, not StrokeStyle or provenance decoder.
                    declaration = next(i + 1 for i, line in enumerate(source) if i > 100 and 'public init(from decoder:' in line)
                    if min(r[0] for r in owner_regions) < declaration:
                        raise RuntimeError('DrawingProgram decoder mapped before exact declaration')
                count = f['count']
                if not isinstance(count, int) or count < 0:
                    raise RuntimeError('invalid function entry count')
                entries.append({'symbol': f['name'], 'demangled': name, 'entryCount': count,
                    'filenames': filenames, 'regions': regions})
            if len({e['symbol'] for e in entries}) != len(entries):
                raise RuntimeError('duplicate mapped symbol; refusing double count')
            result[key] = {'sourceFile': relative, 'ownerType': owner, 'method': method,
                'availability': 'mapped' if entries else 'unavailable',
                'functionEntryCount': sum(e['entryCount'] for e in entries) if entries else None,
                'aggregation': 'sum distinct exact function symbols/instantiations; never sum regions; generic wrapper/specialization multiplicity may count one logical operation more than once', 'rawMappings': entries}
    return result


def _export_accepted(args):
    meta = verified_build(args.scratch)
    directory = args.scratch / args.name
    record = json.loads((directory / 'run.json').read_text())
    validate_run(directory, record, meta)
    expected = directory / 'profiles' / f'test-{record["pid"]}.profraw'
    merged = directory / 'test.profdata'
    subprocess.run(['xcrun', 'llvm-profdata', 'merge', '-sparse', str(expected), '-o', str(merged)], check=True)
    command = ['xcrun', 'llvm-cov', 'export', meta['binary'], '-instr-profile=' + str(merged)]
    raw = subprocess.check_output(command)
    (directory / 'llvm-export.json').write_bytes(raw)
    data = json.loads(raw)
    counts = mappings(data)
    result = {'schemaVersion': 1, 'llvmExportType': data['type'],
        'llvmExportVersion': data['version'], 'command': command,
        'profileSHA256': sha(expected), 'binarySHA256': meta['binarySHA256'],
        'scope': record['scope'], 'owners': counts,
        'checkpointRefreshDecodeCallsite': checkpoint_region(counts),
        'metricMeaning': 'application-owner function entries, not literal SQLite internal query counts; rows calls prepare, scalar calls rows; execute without values uses sqlite3_exec and may compound statements',
        'unavailableMetrics': ['cumulativeAllocationEvents', 'literalSQLiteInternalQueryCount', 'nativeUIFrameCounters'],
        'rawArchiveDecodeScope': 'DrawingRunEvidenceArchive decoder and DrawingRunEvidenceStore.loadSnapshot entries are separate owners; DrawingProgram entries are not total raw-archive decodes (terminal program is an evidence reference)'}
    control = record['environment'].get('DX_COUNTER_CONTROL')
    def count(key):
        value = counts[key]['functionEntryCount']
        if value is None:
            raise RuntimeError(f'control cannot validate missing mapping {key}')
        return value
    if control == 'noop' and any(v['functionEntryCount'] != 0 for v in counts.values()):
        raise RuntimeError('noop owner mapping missing or nonzero')
    if control == 'program-decode' and count('DrawingProgram.init(from') != 1:
        raise RuntimeError('program decode control did not count exactly one decoder entry')
    if control == 'db-positive':
        for method, wanted in [('rows', 4), ('prepare', 4), ('execute', 1)]:
            if count('PortraitLibraryDatabase.' + method) != wanted:
                raise RuntimeError('DB positive control unexpected constructor+SELECT entries')

    result['acceptance'] = 'accepted'
    result['measurementSHA256'] = record['measurementSHA256']
    write(directory / 'structural.json', result)


def export(args):
    directory = args.scratch / args.name
    if (directory / 'structural.json').exists():
        raise RuntimeError('refusing to overwrite existing structural result')
    # Failed attempts are retained; use a fresh run name instead of replacing
    # rejected diagnostics or accidentally promoting stale LLVM output.
    with (directory / 'export-attempt.json').open('x') as marker:
        json.dump({'acceptance': 'not_established'}, marker)
    try:
        _export_accepted(args)
    except Exception as error:
        write(directory / 'export.rejected.json', {'acceptance': 'rejected', 'reason': str(error)})
        raise



def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--scratch', type=safe_scratch, required=True)
    sub = p.add_subparsers(dest='phase', required=True)
    sub.add_parser('build')
    r = sub.add_parser('run', help='one instrumented fresh process, n=1; never benchmark latency')
    r.add_argument('--name', required=True)
    r.add_argument('--helper-proof', type=Path, help='direct helper PID-profile capability proof; defaults to scratch/direct-helper-diagnostic.json')
    r.add_argument('--helper-observation', type=Path, help='successful actual SwiftPM helper argv observation; defaults to scratch/helper-invocation-observation.json')
    r.add_argument('--corpus', type=Path)
    r.add_argument('--archive-records', type=int, help='required expected terminal record count for --archive')
    r.add_argument('--archive-interrupted', type=int, help='required expected interrupted attempt count for --archive')
    r.add_argument('--photos', type=int, help='required actual corpus photo count for every catalog operation; never inferred from path')
    choice = r.add_mutually_exclusive_group(required=True)
    choice.add_argument('--control', choices=('noop', 'program-decode', 'db-positive'))
    choice.add_argument('--operation', choices=OPERATIONS)
    choice.add_argument('--archive', action='store_true', help='one read-only legacy-loadSnapshot operation; requires explicit expected counts')
    choice.add_argument('--flow-operation', choices=('reopen', 'rename', 'rank', 'prune', 'select', 'generate'),
        help='one first operation after open, synthetic renderer override, no warm repetitions')
    choice.add_argument('--transfer', choices=('v1-native-export', 'v1-first-import', 'v1-reimport'))
    e = sub.add_parser('export')
    e.add_argument('--name', required=True)
    args = p.parse_args()
    if args.phase == 'run' and args.archive and (args.corpus is None or args.archive_records is None or args.archive_records < 0 or args.archive_interrupted is None or args.archive_interrupted < 0):
        p.error('--archive requires --corpus and nonnegative --archive-records/--archive-interrupted')
    if args.phase == 'run' and args.operation and (args.photos is None or args.photos <= 0):
        p.error('catalog operations require explicit positive --photos (40, 1000, or 10000 for frozen DX01 conditions)')
    if hasattr(args, 'name') and not re.fullmatch('[a-zA-Z0-9_-]+', args.name):
        p.error('name must be one safe directory component')
    if getattr(args, 'corpus', None):
        args.corpus = args.corpus.resolve()
        if not str(args.corpus).startswith(('/tmp/adaptiveplotter-dx01-', '/private/tmp/adaptiveplotter-dx01-')):
            p.error('corpus must be a frozen disposable DX01 root')
    {'build': build, 'run': run, 'export': export}[args.phase](args)


if __name__ == '__main__':
    main()
