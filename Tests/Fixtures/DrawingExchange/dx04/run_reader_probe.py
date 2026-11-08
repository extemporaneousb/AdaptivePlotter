#!/usr/bin/env python3
"""New paired reader probes; original DX01/DX04 harnesses and gold stay unchanged.
Normal execution requires external coordinator authorization. Preparation/build/
controls/smoke never imply authorization for normal timings.
"""
import argparse, hashlib, importlib.util, json, math, os, pathlib, shutil, sqlite3, subprocess, sys, time, uuid
sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve()
spec = importlib.util.spec_from_file_location('dx04_original_probe', HERE.with_name('run_metadata_probe.py'))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
EXTRA = ['Tests/PlotterAppTests/DrawingExchangeDX04ReaderProbeTests.swift',
         'Tests/Fixtures/DrawingExchange/dx04/run_reader_probe.py']
OPERATIONS = ['gallery-first-page', 'saved-style-catalog', 'exact-native-reader']
TEST = 'DrawingExchangeDX04ReaderProbeTests/measure'
STARTED = '◇ Test "paired gallery, nonempty styles and exact native selected reader" started.'


def clean_env():
    return {k:v for k,v in os.environ.items() if not k.startswith(('DX', 'LLVM_PROFILE', 'PORTRAIT_', 'FLOW_PORTFOLIO_'))
            and k not in {'STUDIO_CAMPAIGN_EVIDENCE_DIRECTORY', 'DRAW_PORTRAIT_BENCHMARK_DIR', 'DRAWING_EXCHANGE_BENCHMARK', 'DRAWING_EXCHANGE_CORPUS'}}


def metadata_facts(path):
    result = {}
    with sqlite3.connect('file:'+str(path)+'?mode=ro',uri=True) as db:
        for name, in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
            query = 'SELECT * FROM "'+name.replace('"','""')+'"'
            if name == 'state': query += " WHERE key<>'styles'"
            rows = [json.dumps(row,sort_keys=True,separators=(',',':'),default=lambda x:{'blobHex':x.hex()}) for row in db.execute(query)]
            result[name] = hashlib.sha256('\n'.join(sorted(rows)).encode()).hexdigest()
        result['schema'] = hashlib.sha256(json.dumps(db.execute('SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name').fetchall(),separators=(',',':')).encode()).hexdigest()
    return result


def prepare(args):
    workspace = args.workspace.resolve(); snapshot = workspace/'.build/dx04-before/source'
    for relative in EXTRA:
        target = snapshot/relative; target.parent.mkdir(parents=True,exist_ok=True)
        if target.exists() and base.sha(target) != base.sha(workspace/relative): raise RuntimeError('Stopped overlay correction required: '+relative)
        if not target.exists(): shutil.copyfile(workspace/relative,target)
    base.prepare(args)
    config = json.loads((args.root/'config.json').read_text()); gold = pathlib.Path(config['gold'])
    selection = json.loads((gold/'dx01-selection.json').read_text())['drawing']
    with sqlite3.connect('file:'+str(gold/'library-v1.sqlite')+'?mode=ro',uri=True) as db:
        row = db.execute('SELECT candidate_record,source_hash,raster_hash,summary FROM drawing WHERE candidate_id=? AND photo_id=?',
                         (selection['id'],selection['photoID'].lower())).fetchone()
        if row is None: raise RuntimeError('Exact selected binding missing')
        recipe = json.loads(row[3])['recipe']
        if db.execute("SELECT value FROM state WHERE key='styles'").fetchone() is not None: raise RuntimeError('Expected original style state absent')
    styles = [{'id':'d4043000-0000-0000-0000-'+format(i,'012x'),'name':'DX04 synthetic reader style '+str(i),
               'recipe':recipe,'createdAt':0} for i in range(1,4)]
    derivative = args.root/'style-corpus'
    shutil.copytree(gold,derivative)
    before = metadata_facts(derivative/'library-v1.sqlite')
    with sqlite3.connect(derivative/'library-v1.sqlite') as db:
        db.execute("INSERT INTO state(key,value) VALUES('styles',?)",(json.dumps(styles,sort_keys=True,separators=(',',':')),))
    after = metadata_facts(derivative/'library-v1.sqlite')
    if before != after: raise RuntimeError('Derivative changed metadata beyond styles')
    derivative_inventory = base.inventory(derivative)
    delta = {p for p in set(config['goldInventory'])|set(derivative_inventory) if config['goldInventory'].get(p)!=derivative_inventory.get(p)}
    if delta != {'library-v1.sqlite'}: raise RuntimeError('Derivative changed immutable or other files')
    original_pins = json.loads((args.root/'input-pins.json').read_text()); fixtures={}
    for operation in OPERATIONS:
        source = derivative if operation == 'saved-style-catalog' else gold
        pins = {k:original_pins[k] for k in ['bindings','genericBindings','immutableFiles','revision']}
        pins.update(databaseSHA256=base.sha(source/'library-v1.sqlite'),candidateID=selection['id'],photoID=selection['photoID'],
                    programHash=selection['programContentHash'],sourceHash=row[1],selectedRecordBytes=(gold/'records'/row[0]).stat().st_size,
                    selectedSourceBytes=(gold/'assets'/row[1]).stat().st_size,selectedRasterBytes=(gold/'assets'/row[2]).stat().st_size,
                    expectedStyleIDs=[s['id'] for s in styles],expectedStyleNames=[s['name'] for s in styles],
                    expectedStyleDates=[s['createdAt'] for s in styles],expectedRecipeJSON=json.dumps(recipe,sort_keys=True,separators=(',',':')))
        pin_path=args.root/('reader-pins-'+operation+'.json');base.write(pin_path,pins)
        fixtures[operation]={'corpus':str(source),'pins':str(pin_path),'pinsSHA256':base.sha(pin_path),
                             'fixtureKind':'NEW three-style metadata derivative' if operation=='saved-style-catalog' else 'original pinned DX01 small'}
    sequence=[]
    for operation in OPERATIONS:
        for variant in ['after','before']:sequence.append({'variant':variant,'label':variant+'-'+operation+'-warm','operation':operation,'trials':30})
        for fresh in range(20):
            for variant in ['after','before'] if fresh%2 else ['before','after']:
                sequence.append({'variant':variant,'label':variant+'-'+operation+'-fresh-'+str(fresh),'operation':operation,'trials':1})
    report={'schemaVersion':1,'baseConfigSHA256':base.sha(args.root/'config.json'),'extraOverlay':{p:base.sha(workspace/p) for p in EXTRA},
            'derivative':str(derivative),'derivativeInventory':derivative_inventory,'derivativeLogicalMetadataExceptStylesBefore':before,
            'derivativeLogicalMetadataExceptStylesAfter':after,'styles':styles,'fixtures':fixtures,'normalPlan':sequence,
            'normalHelpers':126,'normalMeasuredOperations':300,'normalExcludedWarmups':6,'normalMeasurementsAuthorizedByDriver':False,
            'driverUTF8':HERE.read_text(),'driverSHA256':base.sha(HERE),
            'scope':'Host-prepared nonempty style derivative, original gold untouched; no new geometry/width/source-free semantics; style/selected probes NEW, gallery existing API'}
    base.write(args.root/'reader-config.json',report)
    stable(args.root,config,report)
    print(json.dumps({'readerRoot':str(args.root),'extraOverlay':report['extraOverlay'],'derivativeDatabaseSHA256':derivative_inventory['library-v1.sqlite'][1],
                      'derivativeOnlyChangedFile':sorted(delta),'syntheticStyles':len(styles),'selectedAssetBytes':pins['selectedSourceBytes']+pins['selectedRasterBytes']}),flush=True)


def stable(root,config,reader):
    base.stable(config)
    if base.sha(root/'config.json') != reader['baseConfigSHA256']: raise RuntimeError('Base source/input config changed')
    workspace=pathlib.Path(config['workspace']);snapshot=pathlib.Path(config['snapshot'])
    for relative,digest in reader['extraOverlay'].items():
        if base.sha(workspace/relative)!=digest or base.sha(snapshot/relative)!=digest:raise RuntimeError('Extra identical overlay changed')
    if base.inventory(pathlib.Path(reader['derivative']))!=reader['derivativeInventory']:raise RuntimeError('Pinned derivative changed')
    if base.sha(HERE)!=reader['driverSHA256'] or HERE.read_text()!=reader['driverUTF8']:raise RuntimeError('Frozen reader driver changed')
    for fixture in reader['fixtures'].values():
        if base.sha(fixture['pins'])!=fixture['pinsSHA256']:raise RuntimeError('Host reader pins changed')


def reader_run(args,config,reader,variant,label,phase,operation,trials):
    stable(args.root,config,reader)
    build=json.loads((args.root/('build-'+variant+'.json')).read_text());fixture=reader['fixtures'][operation]
    if build['exitCode']!=0 or base.sha(build['image'])!=build['imageSHA256']:raise RuntimeError('Reader build image changed')
    case=args.root/label;case.mkdir(exist_ok=False)
    command=['/Library/Developer/CommandLineTools/usr/libexec/swift/pm/swiftpm-testing-helper','--test-bundle-path',build['image'],'--no-parallel',
             '--filter',TEST,build['image'],'--testing-library','swift-testing']
    token=str(uuid.uuid4());env=clean_env();env.update(DX04_READER_PROBE='1',DX04_PROBE_PHASE='measure',DX04_PROBE_COLLECTION=phase,
      DX04_PROBE_OPERATION=operation,DX04_PROBE_TRIALS=str(trials),DX04_PROBE_TOKEN=token,DX04_EXPECTED_IMAGE=build['image'],DX04_EXPECTED_IMAGE_SHA256=build['imageSHA256'],
      DX04_IDENTITY_OUTPUT=str(case/'identity.json'),DX04_IDENTITY_ACK=str(case/'ack.json'),DX04_PROBE_OUTPUT=str(case/'measurement.json'),
      DX04_CORPUS=fixture['corpus'],DX04_WORK_LIBRARY=str(case/'work/library'),DX04_INPUT_PINS=fixture['pins'],DX04_INPUT_PINS_SHA256=fixture['pinsSHA256'])
    started=time.time();load=os.getloadavg();identity=None;ps=None;failure=None
    with (case/'helper.log').open('x') as output:
        child=subprocess.Popen(command,cwd=config['workspace'],env=env,stdout=output,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+30
            while not (case/'identity.json').exists() and child.poll() is None and time.monotonic()<deadline:time.sleep(.01)
            identity=json.loads((case/'identity.json').read_text());images=identity['testImages']
            if identity['pid']!=child.pid or identity['token']!=token or identity['argv']!=command or len(images)!=1 or pathlib.Path(images[0]['path']).resolve()!=pathlib.Path(build['image']).resolve() or images[0]['sha256']!=build['imageSHA256'] or not images[0].get('uuid'):raise RuntimeError('Actual reader identity/image/filter mismatch')
            ps=subprocess.check_output(['ps','-p',str(child.pid),'-o','pid=,ppid=,command='],text=True).strip();fields=ps.split(None,2)
            if int(fields[0])!=child.pid or int(fields[1])!=os.getpid() or identity['parentPID']!=os.getpid():raise RuntimeError('Actual reader ancestry mismatch')
            base.write(case/'ack.json',{'token':token,'pid':child.pid,'testImageSHA256':build['imageSHA256']})
            code=child.wait(timeout=180)
        except Exception as error:failure=str(error);child.kill();child.wait();code=child.returncode
    log=(case/'helper.log').read_text();result=json.loads((case/'measurement.json').read_text()) if (case/'measurement.json').exists() else None
    if failure is None:
        try:
            if code!=0 or result is None or log.count(STARTED)!=1:raise RuntimeError('Reader did not execute exactly one successful selected test')
            if result['identity']['pid']!=child.pid or result['identity']['argv']!=command or result['identity']['testImages'][0]['sha256']!=build['imageSHA256']:raise RuntimeError('Reader result identity mismatch')
            samples=result['milliseconds']
            if result['collection']!=phase or result['operation']!=operation or result['trials']!=trials or len(samples)!=trials or any(not isinstance(x,(int,float)) or not math.isfinite(x) or x<0 for x in samples):raise RuntimeError('Reader sample mismatch')
            if result['workingCopyDatabaseChanged'] or not result['revisionUnchanged'] or not result['existingImmutableFilesUnchanged'] or result['writerLockPresentAfterSetup']:raise RuntimeError('Reader changed immutable/mutable authority or setup ownership')
            for counter in result['counters']:
                if counter['candidateRecordBytesEncoded'] or counter['metadataBytesEncoded'] or counter['assetBytesVerified']!=(6961 if operation=='exact-native-reader' else 0):raise RuntimeError('Reader categories unexpected')
            if operation=='saved-style-catalog' and result['styleCount']!=3:raise RuntimeError('Nonempty styles missing')
        except Exception as error:failure=str(error)
    receipt={'phase':phase,'variant':variant,'label':label,'operation':operation,'trials':trials,'command':command,'helperPID':child.pid,
             'imageSHA256':build['imageSHA256'],'helperExecutableSHA256':base.sha(command[0]),'identity':identity,'actualPS':ps,'exitCode':code,
             'accepted':failure is None,'rejection':failure,'elapsedSeconds':time.time()-started,'hostLoadBefore':load,'hostLoadAfter':os.getloadavg(),
             'fixture':fixture,'extraOverlay':reader['extraOverlay']}
    base.write(case/'process.json',receipt);stable(args.root,config,reader)
    print(label,'accepted' if failure is None else failure,flush=True)
    if failure:raise RuntimeError(label+': '+failure)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('phase',choices=['prepare','build','controls','smoke','measure']);parser.add_argument('--root',type=pathlib.Path,required=True);parser.add_argument('--workspace',type=pathlib.Path,default=pathlib.Path.cwd());args=parser.parse_args()
    if not str(args.root).startswith('/tmp/adaptiveplotter-dx01-dx04-'):raise RuntimeError('New disposable reader root required')
    sanitized=clean_env();os.environ.clear();os.environ.update(sanitized)
    if args.phase=='prepare':prepare(args);return
    config=json.loads((args.root/'config.json').read_text());reader=json.loads((args.root/'reader-config.json').read_text());stable(args.root,config,reader)
    if args.phase=='build':base.build(args,config);stable(args.root,config,reader);return
    if args.phase=='controls':
        for variant in ['before','after']:
            for control in ['positive','wrong-pid','wrong-image']:
                base.helper_run(args,config,variant,variant+'-control-'+control,'control',control=control);stable(args.root,config,reader)
        return
    if args.phase=='smoke':
        for variant in ['before','after']:
            for operation in OPERATIONS:reader_run(args,config,reader,variant,variant+'-excluded-smoke-'+operation,'smoke',operation,1)
        return
    # External coordinator authorization is required; the driver does not confer it.
    for item in reader['normalPlan']:
        reader_run(args,config,reader,item['variant'],item['label'],'measure',item['operation'],item['trials'])
    base.write(args.root/'reader-normal-complete.json',{'helpers':126,'measuredOperations':300,'excludedWarmups':6,'fullFrozenPlanCompleted':True,'driverSHA256':reader['driverSHA256']})

if __name__=='__main__':main()
