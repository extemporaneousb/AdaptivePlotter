#!/usr/bin/env python3
"""DX04 paired normal clocks, explicit identity/counter controls, disposable inputs only.
No production archive, rendering, native app, hardware or SwiftPM recursion in helpers.
"""
import argparse, hashlib, json, math, os, pathlib, platform, shutil, sqlite3, subprocess, time, uuid

FILES = ['Tests/PlotterAppTests/DrawingExchangeDX04Identity.swift',
         'Tests/PlotterAppTests/DrawingExchangeDX04ProbeTests.swift',
         'Tests/Fixtures/DrawingExchange/dx04/run_metadata_probe.py']
BASE = '56180604569843fbc16ff450ef66142b15a5ebb0'
OPERATIONS = ['photo-first-page', 'photo-filtered-drawing-page', 'gallery-first-page', 'retention-metadata-save']


def sha(path):
    h = hashlib.sha256()
    with pathlib.Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''): h.update(chunk)
    return h.hexdigest()


def write(path, value):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists(): raise RuntimeError('Refusing existing artifact: ' + str(path))
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def inventory(root):
    result = {}
    for path in sorted(pathlib.Path(root).rglob('*')):
        if path.is_symlink(): raise RuntimeError('Unexpected fixture link: ' + str(path))
        if path.is_file() and not path.name.endswith(('.lock', '-journal', '-wal', '-shm')):
            result[str(path.relative_to(root))] = [path.stat().st_size, sha(path)]
    return result


def clean_env():
    return {k:v for k,v in os.environ.items() if not k.startswith(('DX', 'LLVM_PROFILE', 'PORTRAIT_VERIFY_', 'PORTRAIT_RECONCILE_'))
            and k not in {'PORTRAIT_REAL_PILOT_ROOT', 'DRAW_PORTRAIT_BENCHMARK_DIR'}}


def observed_sources(workspace):
    paths = set(subprocess.check_output(['git','ls-files'], cwd=workspace, text=True).splitlines()
                + subprocess.check_output(['git','ls-files','--others','--exclude-standard'], cwd=workspace,text=True).splitlines())
    return {p:sha(workspace/p) for p in sorted(paths) if p.endswith(('.swift','.py')) or p == 'Package.swift'}


def prepare(args):
    workspace, root = args.workspace.resolve(), args.root
    if root.exists(): raise RuntimeError('Use a new disposable probe root')
    snapshot = workspace/'.build/dx04-before/source'
    if not snapshot.is_dir(): raise RuntimeError('Before snapshot missing')
    for relative in FILES:
        source, target = workspace/relative, snapshot/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists() and sha(target)!=sha(source): raise RuntimeError('Existing overlay differs; require stopped correction window: ' + str(target))
        if not target.exists(): shutil.copyfile(source, target)
    gold = pathlib.Path('/tmp/adaptiveplotter-dx01-20261106/corpora/small/catalog')
    gold_inventory = inventory(gold)
    original_receipt = pathlib.Path('/tmp/adaptiveplotter-dx01-20261106/receipts/small-before.json')
    original = json.loads(original_receipt.read_text())
    expected = {row[0][len('catalog/'):]:[row[1],row[2]] for row in original['files'] if row[0].startswith('catalog/')}
    if gold_inventory != expected: raise RuntimeError('Pinned original small catalog differs from DX01 inventory')
    root.mkdir(parents=True)
    with sqlite3.connect('file:' + str(gold/'library-v1.sqlite') + '?mode=ro', uri=True) as db:
        bindings = db.execute('SELECT id,photo_id,source_hash,program_hash,candidate_record,historical_record FROM drawing ORDER BY id').fetchall()
        generic = db.execute('SELECT id,reference FROM generic_drawing ORDER BY id').fetchall()
        selection=json.loads((gold/'dx01-selection.json').read_text())['drawing']
        selected=db.execute('SELECT metadata_record FROM drawing WHERE candidate_id=? AND photo_id=?',(selection['id'],selection['photoID'].lower())).fetchone()
        revision=int(db.execute("SELECT value FROM state WHERE key='revision'").fetchone()[0])
        if not selected or not selected[0]:raise RuntimeError('Pinned selected native metadata missing')
    pins = {'bindings':bindings, 'genericBindings':generic,
            'immutableFiles':{p:pair[1] for p,pair in gold_inventory.items() if p.startswith(('assets/','records/'))},
            'databaseSHA256':gold_inventory['library-v1.sqlite'][1], 'selectedMetadataRecord':selected[0], 'revision':revision}
    write(root/'input-pins.json',pins)
    config = {'schemaVersion':1,'baseCommit':BASE,'workspace':str(workspace),'snapshot':str(snapshot),
              'beforeScratch':str(workspace/'.build/dx04-before/build'),'gold':str(gold),'goldInventory':gold_inventory,
              'originalDX01InventoryReceipt':str(original_receipt),'originalDX01InventorySHA256':sha(original_receipt),
              'inputPinsSHA256':sha(root/'input-pins.json'),
              'beforeSources':{str(p.relative_to(snapshot)):sha(p) for p in sorted((snapshot/'Sources').rglob('*.swift'))},
              'basePackageSHA256':sha(snapshot/'Package.swift'),
              'frozenDX01HarnessSHA256':sha(workspace/'Tests/PlotterAppTests/DrawingExchangeBaselineTests.swift'),
              'host':{'platform':platform.platform(),'machine':platform.machine(),'swift':subprocess.check_output(['swift','--version'],text=True),
                      'hardware':subprocess.check_output(['sysctl','hw.model','hw.memsize','hw.ncpu'],text=True),'osBuild':subprocess.check_output(['sw_vers'],text=True),
                      'filesystemCache':'not evicted; copy and host hash pins outside clocks; not OS-cold'},
              'overlay':{p:sha(workspace/p) for p in FILES},
              'sources':observed_sources(workspace),
              'methodProvenance':{'readBodies':'DrawingExchangeBaselineTests.swift catalog()/gallery(); unchanged frozen original; independent per-helper working copy setup',
                                  'writerBody':'NEW paired save(snapshot one selected occurrence,mode:mutationDelta), not a historical DX01 measurement'},
              'normalMeasurementsAuthorizedByDriver':False}
    write(root/'config.json',config)
    print(json.dumps({'prepared':str(root),'overlay':config['overlay'],'nativeBindingRows':len(bindings),'genericRows':len(generic)}))


def stable(config):
    workspace = pathlib.Path(config['workspace'])
    if observed_sources(workspace) != config['sources']: raise RuntimeError('Runtime/test/driver sources changed since freeze')
    for relative, expected in config['overlay'].items():
        if sha(workspace/relative) != expected or sha(pathlib.Path(config['snapshot'])/relative) != expected:
            raise RuntimeError('Paired overlay mismatch: ' + relative)
    if sha(pathlib.Path(config['snapshot'])/'Package.swift')!=config['basePackageSHA256'] or any(sha(pathlib.Path(config['snapshot'])/p)!=expected for p,expected in config['beforeSources'].items()): raise RuntimeError('Before production snapshot changed')
    if inventory(pathlib.Path(config['gold'])) != config['goldInventory']: raise RuntimeError('Original pinned corpus changed')


def build(args, config):
    stable(config)
    workspace = pathlib.Path(config['workspace'])
    for variant in ['before','after']:
        package = pathlib.Path(config['snapshot']) if variant == 'before' else workspace
        scratch = pathlib.Path(config['beforeScratch']) if variant == 'before' else workspace/'.build'
        command = ['swift','build','--build-tests','--package-path',str(package),'--scratch-path',str(scratch)]
        started=time.time()
        with (args.root/('build-'+variant+'.log')).open('x') as output:
            child=subprocess.Popen(command,cwd=workspace,env=clean_env(),stdout=output,stderr=subprocess.STDOUT)
            code=child.wait()
        image=scratch/'x86_64-apple-macosx/debug/AdaptivePlotterPackageTests.xctest/Contents/MacOS/AdaptivePlotterPackageTests'
        receipt={'variant':variant,'command':command,'pid':child.pid,'exitCode':code,'startedEpoch':started,'elapsedSeconds':time.time()-started,
                 'package':str(package),'scratch':str(scratch),'sourceBinding':BASE if variant=='before' else config['sources']}
        if code==0 and image.is_file(): receipt.update(image=str(image),imageSHA256=sha(image))
        write(args.root/('build-'+variant+'.json'),receipt)
        print('build',variant,code,receipt['elapsedSeconds'],flush=True)
        if code: raise RuntimeError('Build failed: '+variant)
        stable(config)


def helper_run(args, config, variant, label, phase, control=None, operation=None, trials=None):
    stable(config)
    build=json.loads((args.root/('build-'+variant+'.json')).read_text())
    if build.get('exitCode')!=0 or sha(build['image'])!=build['imageSHA256']: raise RuntimeError('Build image changed')
    case=args.root/label
    case.mkdir(exist_ok=False)
    helper='/Library/Developer/CommandLineTools/usr/libexec/swift/pm/swiftpm-testing-helper'
    test_filter='DrawingExchangeDX04ProbeTests/'+('control' if phase=='control' else 'measure')
    command=[helper,'--test-bundle-path',build['image'],'--no-parallel','--filter',test_filter,build['image'],'--testing-library','swift-testing']
    token=str(uuid.uuid4());env=clean_env()
    env.update(DX04_PROBE_PHASE="measure" if phase=="smoke" else phase,DX04_PROBE_COLLECTION=phase,DX04_PROBE_TOKEN=token,DX04_EXPECTED_IMAGE=build['image'],
               DX04_EXPECTED_IMAGE_SHA256='0'*64 if control=='wrong-image' else build['imageSHA256'],
               DX04_IDENTITY_OUTPUT=str(case/'identity.json'),DX04_IDENTITY_ACK=str(case/'ack.json'),
               DX04_PROBE_OUTPUT=str(case/'measurement.json'),DX04_CORPUS=config['gold'],
               DX04_WORK_LIBRARY=str(case/'work/library'),DX04_INPUT_PINS=str(args.root/'input-pins.json'),DX04_INPUT_PINS_SHA256=config['inputPinsSHA256'],DX04_VARIANT=variant)
    if control:env['DX04_PROBE_CONTROL']=control
    if operation:env['DX04_PROBE_OPERATION']=operation;env['DX04_PROBE_TRIALS']=str(trials)
    started=time.time();load_before=os.getloadavg();identity=None;ps=None;failure=None
    with (case/'helper.log').open('xb') as output:
        child=subprocess.Popen(command,cwd=config['workspace'],env=env,stdout=output,stderr=subprocess.STDOUT)
        deadline=time.monotonic()+30
        try:
            if control!='wrong-image':
                while not (case/'identity.json').exists() and child.poll() is None and time.monotonic()<deadline:time.sleep(.01)
                identity=json.loads((case/'identity.json').read_text())
                images=identity['testImages']
                if identity['pid']!=child.pid or identity['token']!=token or len(images)!=1 or pathlib.Path(images[0]['path']).resolve()!=pathlib.Path(build['image']).resolve() or images[0]['sha256']!=build['imageSHA256'] or not images[0].get('uuid'):
                    raise RuntimeError('Actual helper PID/token/loaded image mismatch')
                if identity['argv']!=command: raise RuntimeError('Actual helper argv/filter mismatch')
                ps=subprocess.check_output(['ps','-p',str(child.pid),'-o','pid=,ppid=,command='],text=True).strip()
                fields=ps.split(None,2)
                if int(fields[0])!=child.pid or int(fields[1])!=os.getpid() or identity['parentPID']!=os.getpid():raise RuntimeError('Actual helper ancestry mismatch')
                write(case/'ack.json',{'token':token,'pid':child.pid+1 if control=='wrong-pid' else child.pid,'testImageSHA256':build['imageSHA256']})
            code=child.wait(timeout=180)
        except Exception as error:
            failure=str(error);child.kill();child.wait();code=child.returncode
    log=(case/'helper.log').read_text()
    result=json.loads((case/'measurement.json').read_text()) if (case/'measurement.json').exists() else None
    if failure is None:
        try:
            if code!=0 or result is None:raise RuntimeError('Nonzero exit or missing NEW result')
            if log.count('◇ Test "loader binding and positive counter controls" started.')+log.count('◇ Test "paired existing metadata calls and selected retention commit" started.')!=1:raise RuntimeError('Not exactly one selected probe test')
            if result['identity']['pid']!=child.pid or result['identity']['parentPID']!=os.getpid() or result['identity']['argv']!=command or result['identity']['testImages'][0]['sha256']!=build['imageSHA256']:raise RuntimeError('Result actual runtime identity mismatch')
            if phase=='control':
                if result['control']!=control:raise RuntimeError('Control identity')
                if control in ['wrong-pid','wrong-image'] and (not result['expectedRejection'] or result['backendStarted'] or (case/'work/library').exists()):raise RuntimeError('Negative guard touched backend or did not reject')
                if control=='positive' and (result['assetCounterReadPositive']!=1024*1024 or result['candidateRecordEncodePositive']<=0 or result['warmCandidateRecordBytesEncoded']!=0 or result['warmAssetBytesVerified']!=0 or result['metadataBytesEncodedPositive']<=0):raise RuntimeError('Counter positive/zero control')
            else:
                samples=result.get('milliseconds',[])
                if result.get('collection')!=phase or result['operation']!=operation or result['trials']!=trials or len(samples)!=trials or any(not isinstance(x,(float,int)) or not math.isfinite(x) or x<0 for x in samples):raise RuntimeError('Normal sample/operation mismatch')
        except Exception as error:failure=str(error)
    receipt={'phase':phase,'variant':variant,'label':label,'control':control,'operation':operation,'trials':trials,'command':command,'helperPID':child.pid,
             'helperExecutableSHA256':sha(helper),'imageSHA256':build['imageSHA256'],'actualPS':ps,'identity':identity,'exitCode':code,'accepted':failure is None,'rejection':failure,
             'elapsedSeconds':time.time()-started,'hostLoadBefore':load_before,'hostLoadAfter':os.getloadavg(),'sourceOverlay':config['overlay']}
    write(case/'process.json',receipt)
    stable(config)
    print(label,'accepted' if failure is None else failure,flush=True)
    if failure:raise RuntimeError(label+': '+failure)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('phase',choices=['prepare','build','controls','smoke','measure']);parser.add_argument('--workspace',type=pathlib.Path,default=pathlib.Path.cwd());parser.add_argument('--root',type=pathlib.Path,required=True)
    args=parser.parse_args()
    if not str(args.root).startswith('/tmp/adaptiveplotter-dx01-dx04-'):raise RuntimeError('New named disposable DX04 probe root required')
    if args.phase=='prepare':prepare(args);return
    config=json.loads((args.root/'config.json').read_text());stable(config)
    if args.phase=='build':build(args,config);return
    if args.phase=='controls':
        for variant in ['before','after']:
            for control in ['positive','wrong-pid','wrong-image']:helper_run(args,config,variant,variant+'-control-'+control,'control',control=control)
        return
    if args.phase=='smoke':
        for variant in ['before','after']:
            for operation in OPERATIONS:helper_run(args,config,variant,variant+'-excluded-smoke-'+operation,'smoke',operation=operation,trials=1)
        return
    # Operator/coordinator authorization is external to this ordinary driver.
    # No normal timings are generated by prepare/build/controls.
    for operation in OPERATIONS:
        for variant in ['before','after']:
            helper_run(args,config,variant,variant+'-'+operation+'-warm','measure',operation=operation,trials=30)
        for fresh in range(5):
            for variant in ['after','before'] if fresh%2 else ['before','after']:
                helper_run(args,config,variant,variant+'-'+operation+'-fresh-'+str(fresh),'measure',operation=operation,trials=1)

if __name__=='__main__':main()
