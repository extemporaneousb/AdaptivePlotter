#!/usr/bin/env python3
"""DX01 disposable baseline driver. Never opens a production archive or app.
Run from a reviewed task checkout. Recipes/receipts live separately from corpora.
"""
import gzip, tarfile
import argparse, hashlib, json, math, os, pathlib, platform, random, resource, shutil, struct, subprocess, sys, time, zlib

HERE = pathlib.Path(__file__).resolve().parent
OPERATIONS = ('photo-first-page', 'photo-next-page', 'drawing-first-page', 'drawing-next-page',
              'photo-filtered-drawing-page', 'exact-drawing-load', 'large-drawing-load')
SIZES = {'small': 40, 'medium': 1000, 'large': 10000}

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def inventory(root):
    rows, logical, allocated = [], 0, 0
    for p in sorted(root.rglob('*')):
        if not p.is_file() or p.name.endswith(('-journal', '-wal', '-shm', '.lock')):
            continue
        h = hashlib.sha256()
        with p.open('rb') as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b''): h.update(chunk)
        st = p.stat(); logical += st.st_size; allocated += st.st_blocks * 512
        rows.append([str(p.relative_to(root)), st.st_size, h.hexdigest()])
    frozen = json.dumps(rows, separators=(',', ':')).encode()
    return {'rootSHA256': hashlib.sha256(frozen).hexdigest(), 'logicalBytes': logical,
            'allocatedBytes': allocated, 'fileCount': len(rows), 'files': rows}

def validate_measurement(obj, environment):
    if not isinstance(obj, dict): raise RuntimeError('measurement must be an object')
    operation=environment.get('DX_FLOW_OPERATION') or environment.get('DX_BASELINE_OPERATION')
    phase=environment.get('DX_FLOW_PHASE') or environment.get('DX_BASELINE_PHASE','read')
    trials=int(environment.get('DX_BASELINE_TRIALS','30'))
    if environment.get('DX_FLOW_ROOT'):
        if phase=='prepare':
            if obj.get('revision') is None or not obj.get('sources'): raise RuntimeError('wrong Flow preparation receipt')
            return
        if obj.get('operation')!=operation: raise RuntimeError('Flow operation identity mismatch')
        wanted=1 if operation=='reopen' else int(environment.get('DX_FLOW_WARM_TRIALS','30'))
        if len(obj.get('samples',[]))!=wanted: raise RuntimeError('Flow sample count mismatch')
        return
    if phase=='prepare':
        if obj.get('phase')!='prepare': raise RuntimeError('preparation identity mismatch')
        if environment.get('DX_BASELINE_PHOTOS') and obj.get('photos')!=int(environment['DX_BASELINE_PHOTOS']): raise RuntimeError('photo count mismatch')
        if environment.get('DX_ARCHIVE_RECORDS') and obj.get('legacyTerminalRecords')!=int(environment['DX_ARCHIVE_RECORDS']): raise RuntimeError('archive count mismatch')
        return
    if phase=='negative':
        if obj.get('phase')!='negative': raise RuntimeError('negative identity mismatch')
        return
    if environment.get('DX_BASELINE_ROOT'):
        if obj.get('photos')!=int(environment.get('DX_BASELINE_PHOTOS','20')): raise RuntimeError('catalog condition mismatch')
        if obj.get('status')=='not_applicable':
            if operation!='gallery-next-page' or obj.get('pageSize')!=100 or obj.get('photos',100)>=100 or obj.get('trials')!=0:
                raise RuntimeError('invalid not-applicable result')
            return
        if 'measurements' in obj:
            found=obj['measurements']
            if len(found)!=1 or found[0].get('operation')!=operation: raise RuntimeError('catalog operation identity mismatch')
            values=found[0].get('milliseconds',[])
        else:
            if obj.get('operation')!=operation: raise RuntimeError('actor operation identity mismatch')
            values=obj.get('milliseconds',[])
    else:
        expected='legacy-loadSnapshot' if environment.get('DX_ARCHIVE_ROOT') else operation
        if obj.get('operation')!=expected: raise RuntimeError('operation identity mismatch')
        values=obj.get('milliseconds',[])
        if environment.get('DX_ARCHIVE_ROOT'):
            expected_sha=json.loads((pathlib.Path(environment['DX_ARCHIVE_ROOT'])/'selection.json').read_text())['legacySHA256']
            if obj.get('legacySHA256')!=expected_sha: raise RuntimeError('archive corpus digest mismatch')
        if environment.get('DX_TRANSFER_ROOT'):
            if obj.get('inputPackageSHA256')!=environment.get('DX_TRANSFER_EXPECTED_PACKAGE_SHA256'): raise RuntimeError('transfer input digest mismatch')
            if operation=='v1-native-export' and obj.get('actualExportOutput',{}).get('sha256')!=environment.get('DX_TRANSFER_EXPECTED_PACKAGE_SHA256'):
                raise RuntimeError('native export output digest mismatch')
    if len(values)!=trials or any(not isinstance(v,(int,float)) or not math.isfinite(v) or v<0 for v in values):
        raise RuntimeError('measurement sample count/value mismatch')


def invoke(args, name, environment, filter_name, timeout):
    if getattr(args,'label',None): name=args.label+'--'+name
    env={key:value for key,value in os.environ.items() if not key.startswith('DX_')}
    env.update(environment)
    output=args.root/'receipts'/(name+'.json'); log=output.with_suffix('.log'); process=output.with_suffix('.process.json')
    for path in (output,log,process):
        if path.exists(): raise RuntimeError(f'Refusing existing run artifact {path}; use a fresh root or --label')
    env['DX_BASELINE_OUTPUT']=str(output)
    cmd=['/usr/bin/time','-l','swift','test','--skip-build','--no-parallel','--filter',filter_name]
    log.parent.mkdir(parents=True,exist_ok=True)
    flow_before=set(args.root.glob('flow-*.json'))
    started=time.monotonic(); load_before=os.getloadavg(); started_epoch=time.time()
    with log.open('xb') as stream:
        proc=subprocess.Popen(cmd,env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
        status='exited'
        try: code=proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            import signal
            os.killpg(proc.pid,signal.SIGTERM)
            try: proc.wait(timeout=10)
            except subprocess.TimeoutExpired: os.killpg(proc.pid,signal.SIGKILL); proc.wait()
            status,code='timeout',None
    problem=None
    try:
        if code!=0: raise RuntimeError(f'process {status}, exit={code}')
        if environment.get('DX_FLOW_ROOT'):
            emitted=set(args.root.glob('flow-*.json'))-flow_before
            matches=[]
            for path in emitted:
                obj=json.loads(path.read_text())
                if isinstance(obj,dict) and ((environment.get('DX_FLOW_OPERATION') and obj.get('operation')==environment['DX_FLOW_OPERATION']) or path.name=='flow-prepare.json'):
                    matches.append(path)
            if len(matches)!=1: raise RuntimeError(f'expected exactly one NEW matching Flow receipt, found {len(matches)}')
            observed=json.loads(matches[0].read_text())
            if 'firstOperationProgramFile' in observed:
                artifact=args.root/observed['firstOperationProgramFile']
                actual=hashlib.sha256(artifact.read_bytes()).hexdigest()
                if actual!=observed['firstOperationProgramObjectSHA256']: raise RuntimeError(f'producer bytes conflict expected={observed["firstOperationProgramObjectSHA256"]} actual={actual}')
                destination=output.parent/artifact.name
                if destination.exists(): raise RuntimeError('refusing existing producer artifact')
                shutil.move(str(artifact),str(destination))
            with output.open('xb') as target: target.write(matches[0].read_bytes())
            matches[0].unlink()
        if not output.exists(): raise RuntimeError('successful process produced no NEW measurement; zero matching tests is not evidence')
        validate_measurement(json.loads(output.read_text()),environment)
    except (RuntimeError,ValueError,KeyError,OSError) as error: problem=str(error)
    receipt={'command':cmd,'environment':environment,'status':status,'exitCode':code,
        'startedEpochSeconds':started_epoch,'elapsedSeconds':time.monotonic()-started,
        'hostLoadAverageBefore':load_before,'hostLoadAverageAfter':os.getloadavg(),
        'log':str(log),'outputPresent':output.exists(),'measurementAccepted':problem is None,'rejection':problem}
    write(process,receipt)
    print(name,status,code,f'{receipt["elapsedSeconds"]:.2f}s', 'accepted' if problem is None else problem,flush=True)
    if problem: raise RuntimeError(f'{name}: {problem}; see {log}')
    return output

def png(width, height, color, pixels):
    channels = 3 if color == 2 else 1
    rows = b''.join(b'\0'+pixels[y*width*channels:(y+1)*width*channels] for y in range(height))
    def chunk(kind, data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,color,0,0,0))+chunk(b'IDAT',zlib.compress(rows,0))+chunk(b'IEND',b'')

def media(args):
    root = args.root / 'corpora' / 'mixed-media'
    if root.exists(): raise RuntimeError('Refusing existing corpus')
    root.mkdir(parents=True)
    rng = random.Random(7301); records=[]; started=time.monotonic()
    for n in range(1024):
        original = rng.randbytes(2048*1024*3)
        prepared = b''.join(original[y*2048*3:y*2048*3+1024*3:3] for y in range(1024))  # left-half crop, red channel
        for kind, ext, width, height, data in (
            ('original','png',2048,1024,png(2048,1024,2,original)),
            ('prepared','png',1024,1024,png(1024,1024,0,prepared)),
            ('raw-frame','gray8',2048,1536,rng.randbytes(2048*1536))):
            digest=hashlib.sha256(data).hexdigest(); p=root/kind/f'{n:04}-{digest}.{ext}'
            p.parent.mkdir(exist_ok=True); p.write_bytes(data)
            records.append({'path':str(p.relative_to(root)), 'kind':kind, 'width':width,'height':height,
                            'bytes':len(data),'sha256':digest,'synthetic':True,'group':n})
        if n % 128 == 0: print('media groups',n,flush=True)
    write(root/'media-manifest.json',{'seed':7301,'groups':1024,'records':records,
        'evidenceClass':'synthetic storage corpus; no attributable physical capture',
        'limitation':'Pool is separate from hash-only legacy terminals; not an exchange closure or production import/export workload'})
    receipt=inventory(root); receipt['elapsedSeconds']=time.monotonic()-started
    write(args.root/'receipts'/'mixed-media.inventory.json',receipt)
    if receipt['allocatedBytes'] < 10*1024**3: raise RuntimeError('Media allocation below 10GiB')
    print('media allocated',receipt['allocatedBytes'],flush=True)

def main():
    p=argparse.ArgumentParser(); p.add_argument('phase',choices=['prepare','measure','media','inventory','summary','negative','flow-prepare','flow-measure','sql-capability','transfer-prepare','transfer-measure','verify-media','producer-prepare','producer-measure','producer-author','flow-author','transfer-author','supplement'])
    p.add_argument('--root',type=pathlib.Path,required=True); p.add_argument('--condition',choices=SIZES,default='small')
    p.add_argument('--timeout',type=int,default=1800); p.add_argument('--flow-operation'); p.add_argument('--label'); args=p.parse_args()
    args.root=args.root.absolute()
    if not str(args.root).startswith(('/tmp/adaptiveplotter-dx01-','/private/tmp/adaptiveplotter-dx01-')):
        p.error('Use a new /tmp/adaptiveplotter-dx01-* disposable root')
    args.root.mkdir(parents=True,exist_ok=True)
    if args.phase.startswith('producer-'):
        frozen=args.root/'flow-frozen.flowportfolio'; before=inventory(frozen)
        pin_file=HERE/'producer-pin.json'; program_file=HERE/'producer-program.json'
        author=args.phase=='producer-author'
        if author:
            if pin_file.exists() or program_file.exists(): raise RuntimeError('Refusing to overwrite existing producer gold')
            pin=None
        else:
            if not pin_file.is_file() or not program_file.is_file(): raise RuntimeError('Unavailable checked producer gold; normal prepare never authors')
            pin=json.loads(pin_file.read_text()); actual=hashlib.sha256(program_file.read_bytes()).hexdigest()
            if actual!=pin['programObjectSHA256']: raise RuntimeError(f'producer gold conflict expected={pin["programObjectSHA256"]} actual={actual}')
        if args.phase in ('producer-author','producer-prepare'):
            env={'DX_FLOW_ROOT':str(args.root),'DX_FLOW_PHASE':'measure','DX_FLOW_OPERATION':'producer-replay','DX_FLOW_WARM_TRIALS':'0'}
            if pin: env.update(DX_FLOW_REPLAY_CANDIDATE_ID=pin['input']['candidateID'],DX_FLOW_REPLAY_EXPECTED_HASH=pin['expectedProgramHash'])
            observed_path=invoke(args,'producer-author' if author else 'producer-verify',env,'DrawingExchangeFlowBaselineTests',args.timeout)
            actual=json.loads(observed_path.read_text()); program=observed_path.parent/actual['firstOperationProgramFile']
            if pin:
                for key,new in [('inputReceiptSHA256',actual['inputReceiptSHA256']),('programObjectSHA256',actual['firstOperationProgramObjectSHA256']),('expectedProgramHash',actual['firstOperationProgramHash'])]:
                    if pin[key]!=new: raise RuntimeError(f'producer conflict {key}: old={pin[key]} new={new}; diagnostics={observed_path}')
            else:
                shutil.copyfile(program,program_file)
                write(pin_file,{'input':actual['input'],'inputReceiptSHA256':actual['inputReceiptSHA256'],
                    'expectedProgramHash':actual['firstOperationProgramHash'],'programObjectSHA256':actual['firstOperationProgramObjectSHA256'],
                    'programFile':'producer-program.json','sourceReceiptSHA256':hashlib.sha256(observed_path.read_bytes()).hexdigest()})
            return
        for n in range(6):
            observed_path=invoke(args,f'producer-replay-{n}',{'DX_FLOW_ROOT':str(args.root),'DX_FLOW_PHASE':'measure',
                'DX_FLOW_OPERATION':'producer-replay','DX_FLOW_WARM_TRIALS':str(30 if n==0 else 0),
                'DX_FLOW_REPLAY_CANDIDATE_ID':pin['input']['candidateID'],'DX_FLOW_REPLAY_EXPECTED_HASH':pin['expectedProgramHash']},'DrawingExchangeFlowBaselineTests',args.timeout)
            actual=json.loads(observed_path.read_text())
            if actual['inputReceiptSHA256']!=pin['inputReceiptSHA256']: raise RuntimeError('Producer replay input changed')
            if actual['firstOperationProgramObjectSHA256']!=pin['programObjectSHA256']: raise RuntimeError('Producer replay exact bytes changed')
        after=inventory(frozen); write(args.root/'receipts'/'producer-immutability.json',{'before':before,'after':after,'unchanged':before['rootSHA256']==after['rootSHA256']})
        if before['rootSHA256']!=after['rootSHA256']: raise RuntimeError('Producer replay changed frozen portfolio')
        return
    if args.phase.startswith('transfer-'):
        root=args.root/'corpora'/'legacy-transfer'
        if args.phase in ('transfer-prepare','transfer-author'):
            seed=HERE/'legacy-v1.json'; manifest=HERE/'legacy-v1.manifest.json'
            if args.phase=='transfer-author':
                if seed.exists() or manifest.exists(): raise RuntimeError('Refusing to overwrite existing transfer gold')
                path=invoke(args,'transfer-author',{'DX_TRANSFER_ROOT':str(root),'DX_TRANSFER_CATALOG':str(args.root/'corpora'/'small'/'catalog'),'DX_BASELINE_PHASE':'prepare'},'DrawingExchangeBaselineTests',args.timeout)
                shutil.copyfile(root/'legacy-v1.json',seed); write(manifest,json.loads(path.read_text()))
            else:
                if not seed.is_file() or not manifest.is_file(): raise RuntimeError('Unavailable checked transfer gold; normal prepare never authors')
                expected=json.loads(manifest.read_text()); actual=hashlib.sha256(seed.read_bytes()).hexdigest()
                if actual!=expected['packageSHA256']: raise RuntimeError(f'transfer gold conflict expected={expected["packageSHA256"]} actual={actual}')
                if root.exists(): raise RuntimeError('Refusing existing transfer corpus')
                root.mkdir(parents=True); shutil.copyfile(seed,root/'legacy-v1.json')
            write(args.root/'receipts'/'transfer-before.json',inventory(root)); return
        before=inventory(root)
        transfer_expected=json.loads((HERE/'legacy-v1.manifest.json').read_text())
        for operation in ['v1-native-export','v1-first-import','v1-reimport']:
            for mode,trials,repetitions in [('warm',30,1),('process-cold',1,5)]:
                for n in range(repetitions):
                    invoke(args,f'{operation}-{mode}-{n}',{'DX_TRANSFER_ROOT':str(root),'DX_BASELINE_PHASE':'measure',
                        'DX_BASELINE_OPERATION':operation,'DX_BASELINE_TRIALS':str(trials),
                        'DX_TRANSFER_EXPECTED_PROGRAM_HASH':transfer_expected['programHash'],
                        'DX_TRANSFER_EXPECTED_PACKAGE_SHA256':transfer_expected['packageSHA256']},'DrawingExchangeBaselineTests',args.timeout)
        after=inventory(root)
        write(args.root/'receipts'/'transfer-immutability.json',{'before':before,'after':after,'unchanged':before['rootSHA256']==after['rootSHA256']})
        if before['rootSHA256']!=after['rootSHA256']: raise RuntimeError('Frozen transfer fixture mutated')
        return
    if args.phase=='sql-capability':
        import ctypes
        sqlite=ctypes.CDLL('/usr/lib/libsqlite3.dylib')
        callback=ctypes.CFUNCTYPE(ctypes.c_int,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p)(lambda *_: 0)
        sqlite.sqlite3_auto_extension.argtypes=[ctypes.c_void_p]; sqlite.sqlite3_auto_extension.restype=ctypes.c_int
        code=sqlite.sqlite3_auto_extension(ctypes.cast(callback,ctypes.c_void_p))
        if code==0:
            sqlite.sqlite3_cancel_auto_extension.argtypes=[ctypes.c_void_p]
            sqlite.sqlite3_cancel_auto_extension(ctypes.cast(callback,ctypes.c_void_p))
        receipt={'sqliteCode':code,'supported':code==0,'queryCount':None,'decodeCount':None,
                 'status':'available-unmeasured' if code==0 else 'unsupported',
                 'limitation':'Apple SQLite process-global auto extensions unavailable; no query-count evidence'}
        write(args.root/'receipts'/'sql-capability.json',receipt); print(json.dumps(receipt)); return
    if args.phase.startswith('flow-'):
        frozen = args.root/'flow-frozen.flowportfolio'
        seed = HERE/'flow-seed.tar.gz'
        if args.phase in ('flow-prepare','flow-author'):
            author=args.phase=='flow-author'
            if author and (seed.exists() or (HERE/'flow-seed.manifest.json').exists()): raise RuntimeError('Refusing to overwrite existing Flow gold')
            if not author and (not seed.is_file() or not (HERE/'flow-seed.manifest.json').is_file()): raise RuntimeError('Unavailable checked Flow gold; normal prepare never authors')
            if frozen.exists(): raise RuntimeError('Refusing existing frozen Flow corpus')
            if not author:
                expected=json.loads((HERE/'flow-seed.manifest.json').read_text())
                if hashlib.sha256(seed.read_bytes()).hexdigest()!=expected['seedSHA256']: raise RuntimeError('Frozen seed archive digest mismatch')
                with tarfile.open(seed) as t:
                    for member in t.getmembers():
                        if not member.isfile() or pathlib.PurePosixPath(member.name).is_absolute() or '..' in pathlib.PurePosixPath(member.name).parts:
                            raise RuntimeError('Invalid frozen fixture member')
                    t.extractall(frozen)
                actual=inventory(frozen)
                if actual['rootSHA256']!=expected['rootSHA256']: raise RuntimeError('Frozen Flow corpus integrity mismatch')
                write(args.root/'receipts'/'flow-installed-seed.json',actual)
            else:
                invoke(args,'flow-prepare',{'DX_FLOW_ROOT':str(args.root),'DX_FLOW_PHASE':'prepare'},
                       'DrawingExchangeFlowBaselineTests',args.timeout)
                with seed.open('wb') as raw, gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0) as compressed:
                    with tarfile.open(fileobj=compressed,mode='w') as archive:
                        for path in sorted(frozen.rglob('*')):
                            if not path.is_file() or path.name.endswith('.lock'): continue
                            info=archive.gettarinfo(str(path),str(path.relative_to(frozen)))
                            info.uid=info.gid=0; info.uname=info.gname=''; info.mtime=0; info.mode=0o600
                            with path.open('rb') as source: archive.addfile(info,source)
                manifest=inventory(frozen); manifest['seedSHA256']=hashlib.sha256(seed.read_bytes()).hexdigest()
                write(HERE/'flow-seed.manifest.json',manifest)
            return
        before=inventory(frozen)
        operations=[args.flow_operation] if args.flow_operation else ['reopen','view','select','choose','refine','prune','rename','rank','generate','failed-rank','equal-byte-capture','real-generate']
        for operation in operations:
            for n in range(5 if operation=='reopen' else 6):
                invoke(args,f'flow-{operation}-{n}',{'DX_FLOW_ROOT':str(args.root),'DX_FLOW_PHASE':'measure','DX_FLOW_OPERATION':operation, 'DX_FLOW_WARM_TRIALS':str(30 if n == 0 else 0)},
                       'DrawingExchangeFlowBaselineTests',args.timeout)
        after=inventory(frozen)
        write(args.root/'receipts'/'flow-immutability.json',{'before':before,'after':after,'unchanged':before['rootSHA256']==after['rootSHA256']})
        if before['rootSHA256']!=after['rootSHA256']: raise RuntimeError('Frozen Flow corpus mutated')
        return
    if args.phase=='media': return media(args)
    if args.phase=='verify-media':
        before=json.loads((args.root/'receipts'/'mixed-media.inventory.json').read_text())
        after=inventory(args.root/'corpora'/'mixed-media')
        receipt={'beforeRootSHA256':before['rootSHA256'],'afterRootSHA256':after['rootSHA256'],'unchanged':before['rootSHA256']==after['rootSHA256'],'allocatedBytes':after['allocatedBytes']}
        write(args.root/'receipts'/'mixed-media-immutability.json',receipt)
        if not receipt['unchanged']: raise RuntimeError('Frozen mixed media mutated')
        return
    if args.phase=='inventory':
        write(args.root/'receipts'/f'{args.condition}-inventory.json',inventory(args.root/'corpora'/args.condition)); return
    if args.phase=='summary':
        rows=[]
        for path in sorted((args.root/'receipts').glob('*.json')):
            obj=json.loads(path.read_text())
            if not isinstance(obj,dict): continue
            if 'samples' in obj and isinstance(obj['samples'],list):
                flow_times=sorted(sample['seconds']*1000 for sample in obj['samples'] if 'seconds' in sample)
                if flow_times:
                    rows.append({'receipt':path.name,'operation':obj.get('operation'), 'kind':'process-cold-reopen' if obj.get('operation')=='reopen' else 'warm',
                        'n':len(flow_times),'p50MS':flow_times[math.ceil(len(flow_times)*.5)-1],
                        'p95MS':flow_times[math.ceil(len(flow_times)*.95)-1],
                        'processPeakRSSBytes':obj.get('processLifetimePeakRSSBytes')})
                elif obj.get('firstOperationAfterOpenSeconds') is not None:
                    rows.append({'receipt':path.name,'operation':obj.get('operation'),'kind':'first-operation-after-open',
                        'n':1,'p50MS':obj['firstOperationAfterOpenSeconds']*1000,
                        'p95MS':obj['firstOperationAfterOpenSeconds']*1000,
                        'processPeakRSSBytes':obj.get('processLifetimePeakRSSBytes')})
            for m in obj.get('measurements', [obj] if 'milliseconds' in obj else []):
                times=sorted(m.get('milliseconds',[]))
                if times: rows.append({'receipt':path.name,'operation':m.get('operation'), 'n':len(times),
                    'p50MS':times[math.ceil(len(times)*.5)-1],'p95MS':times[math.ceil(len(times)*.95)-1],
                    'processPeakRSSBytes':obj.get('processPeakRSSBytes')})
        write(args.root/'receipts'/'summary.json',rows); print(json.dumps(rows,indent=2)); return
    count=SIZES[args.condition]; corpus=args.root/'corpora'/args.condition
    catalog=corpus/'catalog'; archive=corpus/'archive'
    common={'DX_BASELINE_PHASE':args.phase}
    if args.phase=='supplement':
        before=inventory(corpus)
        for operation in ['gallery-first-page','gallery-next-page','identity-drawing-load']:
            for mode,trials,repetitions in [('warm',30,1),('process-cold',1,5)]:
                for n in range(repetitions):
                    invoke(args,f'{args.condition}-{operation}-{mode}-{n}',dict(common,DX_BASELINE_ROOT=str(catalog),
                        DX_BASELINE_PHOTOS=str(count),DX_BASELINE_OPERATION=operation,DX_BASELINE_TRIALS=str(trials)),
                        'DrawingExchangeBaselineTests',args.timeout)
        after=inventory(corpus)
        path=args.root/'receipts'/f'{args.condition}-supplement-immutability.json'
        write(path,{'before':before,'after':after,'unchanged':before['rootSHA256']==after['rootSHA256']})
        if before['rootSHA256']!=after['rootSHA256']: raise RuntimeError('Supplement changed gold corpus')
        return
    if args.phase=='prepare':
        host={'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
              'platform':platform.platform(),'machine':platform.machine(),
              'hardware':subprocess.check_output(['sysctl','hw.model','hw.memsize','hw.ncpu'],text=True).strip(),
              'osBuild':subprocess.check_output(['sw_vers'],text=True).strip(),
              'swift':subprocess.check_output(['swift','--version'],text=True).strip(),
              'build':'debug; swift test --no-parallel; skip-build during measurement',
              'harnessSHA256':{str(path.relative_to(HERE.parents[3])):hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted(HERE.parents[3].glob('Tests/**/*DrawingExchange*BaselineTests.swift'))},
              'cache':'filesystem cache uncontrolled; no eviction', 'seed':7301,
              'storage':subprocess.check_output(['df','-h',str(args.root)],text=True).strip()}
        write(args.root/'receipts'/'host.json',host)
        invoke(args,args.condition+'-catalog-prepare',dict(common,DX_BASELINE_ROOT=str(catalog),DX_BASELINE_PHOTOS=str(count)),
               'DrawingExchangeBaselineTests',args.timeout)
        records=100000 if args.condition=='large' else (10000 if args.condition=='medium' else 100)
        time_manifest=json.loads((HERE/'archive-times.manifest.json').read_text())[args.condition]
        compressed=(HERE/time_manifest['filename']).read_bytes()
        if hashlib.sha256(compressed).hexdigest()!=time_manifest['sha256']: raise RuntimeError('Timestamp fixture compressed digest mismatch')
        times=gzip.decompress(compressed)
        if hashlib.sha256(times).hexdigest()!=time_manifest['decodedSHA256']: raise RuntimeError('Timestamp fixture decoded digest mismatch')
        time_path=args.root/'receipts'/('archive-times-'+args.condition+'.json')
        time_path.parent.mkdir(parents=True,exist_ok=True); time_path.write_bytes(times)
        invoke(args,args.condition+'-archive-prepare',dict(common,DX_ARCHIVE_TIMES=str(time_path),DX_ARCHIVE_ROOT=str(archive),DX_ARCHIVE_RECORDS=str(records),
            DX_ARCHIVE_INTERRUPTED=str(1000 if args.condition=='large' else 10),DX_ARCHIVE_SEED=str(HERE/'archive-seed.json')),
               'DrawingExchangeArchiveBaselineTests',args.timeout)
        write(args.root/'receipts'/f'{args.condition}-before.json',inventory(corpus))
        return
    before=inventory(corpus)
    if args.phase=='negative':
        invoke(args,args.condition+'-catalog-negative',dict(common,DX_BASELINE_ROOT=str(catalog),DX_BASELINE_PHOTOS=str(count)),
               'DrawingExchangeBaselineTests',args.timeout)
        invoke(args,args.condition+'-archive-negative',dict(common,DX_ARCHIVE_ROOT=str(archive)),
               'DrawingExchangeArchiveBaselineTests',args.timeout)
        after=inventory(corpus)
        write(args.root/'receipts'/f'{args.condition}-negative-immutability.json',
              {'before':before,'after':after,'unchanged':before['rootSHA256']==after['rootSHA256']})
        if before['rootSHA256']!=after['rootSHA256']: raise RuntimeError('Negative mutated frozen corpus')
        return
    for operation in OPERATIONS:
        for mode,trials,repetitions in [('warm',30,1),('process-cold',1,5)]:
            for n in range(repetitions):
                invoke(args,f'{args.condition}-{operation}-{mode}-{n}',dict(common,DX_BASELINE_ROOT=str(catalog),
                    DX_BASELINE_PHOTOS=str(count),DX_BASELINE_OPERATION=operation,DX_BASELINE_TRIALS=str(trials)),
                       'DrawingExchangeBaselineTests',args.timeout)
    for mode,trials,repetitions in [('warm',30,1),('process-cold',1,5)]:
        for n in range(repetitions):
            invoke(args,f'{args.condition}-archive-{mode}-{n}',dict(common,DX_ARCHIVE_ROOT=str(archive),DX_BASELINE_TRIALS=str(trials),DX_BASELINE_PROGRESS='1'),
                   'DrawingExchangeArchiveBaselineTests',args.timeout)
    after=inventory(corpus)
    write(args.root/'receipts'/f'{args.condition}-immutability.json',{'before':before,'after':after,
        'unchanged':before['rootSHA256']==after['rootSHA256']})
    if before['rootSHA256']!=after['rootSHA256']: raise RuntimeError('Baseline corpus mutated')

if __name__=='__main__': main()
