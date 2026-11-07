#!/usr/bin/env python3
"""Disposable DX03 full-admission measurement/control driver; never builds.
Actual helper PID/ancestry and loaded artifact are attested before operations.
Filesystem cache is uncontrolled. Process-warm RSS is a shared lifetime peak.
"""
import argparse, copy, hashlib, json, math, os, pathlib, platform, shlex, struct, subprocess, time, uuid, zipfile
HERE = pathlib.Path(__file__).resolve().parent
BAGIT = b'BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n'
def require(value, message):
    if not value: raise ValueError(message)
def sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
    return digest.hexdigest()
def write_json(path,value):
    require(not path.exists(),'existing artifact label: '+str(path))
    path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
def inventory(root):
    files={}
    for path in sorted(root.rglob('*')):
        if path.is_file():
            s=path.stat();require(not path.is_symlink() and s.st_nlink==1,'corpus link')
            files[str(path.relative_to(root))]={'bytes':s.st_size,'allocatedBytes':s.st_blocks*512,'sha256':sha(path),'mtimeNS':s.st_mtime_ns,'ctimeNS':s.st_ctime_ns}
    return {'files':files,'logicalBytes':sum(r['bytes'] for r in files.values()),'allocatedBytes':sum(r['allocatedBytes'] for r in files.values())}
def metadata(root):
    return {str(p.relative_to(root)):(p.stat().st_size,p.stat().st_mtime_ns,p.stat().st_ctime_ns,p.stat().st_ino,p.stat().st_nlink) for p in sorted(root.rglob('*')) if p.is_file()}
def prepare(args):
    require(args.frames>0 and args.width>0 and args.height>0,'dimensions/count')
    frame_bytes=args.frame_bytes or args.width*args.height
    require(frame_bytes%args.height==0 and frame_bytes//args.height>=args.width,'frame stride')
    args.root.mkdir(parents=True,exist_ok=False);source=args.root/'source';source.mkdir()
    fixture=HERE.parent/'v1/source-free.zip';require(sha(fixture)=='da5b913b8d946958dcc03dc4beddca0394052b539af3298667c521be3dd61c25','frozen fixture changed')
    rows={}
    # Exact frozen trusted fixture baseline; untrusted transport admission is never zipfile extraction.
    with zipfile.ZipFile(fixture) as archive:
        for name in archive.namelist():
            if name.startswith('data/'):
                raw=archive.read(name);path=source/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw);rows[name]=hashlib.sha256(raw).hexdigest()
    index=json.loads((source/'data/exchange.json').read_bytes());index.setdefault('requiredFeatures',[]);frame_digests=[]
    for n in range(args.frames):
        temporary=source/f'frame-{n}.tmp';digest=hashlib.sha256();block=hashlib.shake_256(f'DX03-frame-{n}'.encode()).digest(1024*1024);remaining=frame_bytes
        with temporary.open('xb') as output:
            while remaining:
                chunk=block[:min(len(block),remaining)];output.write(chunk);digest.update(chunk);remaining-=len(chunk)
        value=digest.hexdigest();name='data/objects/sha256/'+value;temporary.rename(source/name);rows[name]=value;frame_digests.append(value)
        index['assets'].append({'object':value,'byteLength':frame_bytes,'mediaType':'application/octet-stream','encoding':'raw-gray8',
          'dimensions':{'width':args.width,'height':args.height},'pixelLayout':{'width':args.width,'height':args.height,'pixelFormat':'gray','componentType':'uint8','bitDepth':8,'channelOrder':['gray'],'rowStride':frame_bytes//args.height,'byteOrder':'not-applicable','orientation':'up','colorInterpretation':'linear-gray'}})
    require(len(set(frame_digests))==args.frames,'raw frames must be distinct blobs')
    (source/'data/exchange.json').write_text(json.dumps(index,indent=2,sort_keys=True)+'\n');rows['data/exchange.json']=sha(source/'data/exchange.json')
    (source/'bagit.txt').write_bytes(BAGIT);manifest=''.join(d+'  '+p+'\n' for p,d in sorted(rows.items())).encode();(source/'manifest-sha256.txt').write_bytes(manifest)
    (source/'tagmanifest-sha256.txt').write_text(''.join(hashlib.sha256(raw).hexdigest()+'  '+name+'\n' for name,raw in [('bagit.txt',BAGIT),('manifest-sha256.txt',manifest)]))
    measured=inventory(source);raw_allocated=sum((source/('data/objects/sha256/'+d)).stat().st_blocks*512 for d in frame_digests)
    require(raw_allocated>=args.frames*frame_bytes,'sparse/underallocated raw corpus')
    write_json(args.root/'recipe.json',{'schemaVersion':2,'frames':args.frames,'frameBytes':frame_bytes,'rawBytes':args.frames*frame_bytes,'width':args.width,'height':args.height,'rowStride':frame_bytes//args.height,'rawAllocatedBytes':raw_allocated,'distinctRawDigests':len(set(frame_digests)),'evidenceClass':'deterministic synthetic raw frames, no camera captures','allocation':'ordinary writes, no sparse files/hardlinks','inventory':measured})
def artifact(path):
    path=path.resolve();size=path.stat().st_size
    with path.open('rb') as stream:
        head=stream.read(32);require(len(head)==32 and struct.unpack_from('<I',head)[0]==0xfeedfacf,'expected native64-bit MachO artifact')
        count,length=struct.unpack_from('<II',head,16);require(count<65536 and length<=1024*1024,'MachO identity bounds');commands=stream.read(length)
    offset=0;identity=None
    for _ in range(count):
        require(offset+8<=len(commands),'MachO command extent');kind,n=struct.unpack_from('<II',commands,offset);require(n>=8 and offset+n<=len(commands),'MachO command size')
        if kind==0x1b:require(n>=24,'UUID command');identity=str(uuid.UUID(bytes=commands[offset+8:offset+24]))
        offset+=n
    require(identity,'artifact UUID missing')
    return {'path':str(path),'sha256':sha(path),'loadedMachOUUID':identity,'bytes':size}
def observe_pid(pid,launcher):
    chain=[];current=pid
    for _ in range(20):
        line=subprocess.run(['/bin/ps','-ww','-p',str(current),'-o','pid=','-o','ppid=','-o','command='],capture_output=True,text=True,check=False).stdout.strip()
        require(line,'helper PID is stale/not alive');parts=line.split(None,2);require(len(parts)==3,'PID observation shape')
        observed,parent=int(parts[0]),int(parts[1]);require(observed==current,'PID observation mismatch');chain.append({'pid':observed,'ppid':parent,'command':parts[2]})
        if current==launcher:return chain
        require(current>1 and parent!=current,'helper not descended from launched Swift process');current=parent
    raise ValueError('helper ancestry exceeds bound')
def validate_identity(identity,expected,token,launcher):
    require(identity['token']==token,'stale helper token');pid=identity['pid'];require(type(pid)is int and pid>0,'PID type/range')
    require(pid!=launcher,'launcher wrapper is not actual test helper')
    images=identity['testImages'];require(len(images)==1,'loaded test image count');image=images[0]
    require(str(pathlib.Path(image['path']).resolve())==expected['path'],'wrong loaded test image path')
    require(image['sha256']==expected['sha256'] and image['loadedMachOUUID']==expected['loadedMachOUUID'],'wrong/stale loaded test artifact SHA/UUID')
    require(type(identity['argv'])is list and bool(identity['argv']),'helper argv missing')
    chain=observe_pid(pid,launcher)
    observed_argv=shlex.split(chain[0]['command']);reported_argv=identity['argv']
    require(observed_argv==reported_argv,'reported helper argv differs from live process command')
    require(str(pathlib.Path(observed_argv[0]).resolve())==str(pathlib.Path(identity['mainExecutablePath']).resolve()),'reported main executable differs from live helper command')
    require(pathlib.Path(observed_argv[0]).name=='swiftpm-testing-helper','actual process is not SwiftPM test helper')
    return chain
def identity_controls(identity,expected,token,launcher):
    results=[]
    mutations={'wrong-wrapper-pid':lambda x:x.update(pid=launcher),'wrong-helper-argv':lambda x:x['argv'].append('--stale-argv'),'wrong-main-executable':lambda x:x.update(mainExecutablePath='/bin/sh'),'wrong-pid':lambda x:x.update(pid=os.getpid()),'stale-pid':lambda x:x.update(pid=2147483647),'stale-token':lambda x:x.update(token='stale'),
      'wrong-image-sha':lambda x:x['testImages'][0].update(sha256='0'*64),'stale-image-uuid':lambda x:x['testImages'][0].update(loadedMachOUUID=str(uuid.UUID(int=0))),
      'wrong-image-path':lambda x:x['testImages'][0].update(path='/tmp/wrong-loaded-test-image')}
    for name,change in mutations.items():
        value=copy.deepcopy(identity);change(value)
        try:validate_identity(value,expected,token,launcher)
        except (ValueError,OSError,KeyError) as error:results.append({'control':name,'rejected':True,'reason':str(error)})
        else:raise ValueError('identity rejection control accepted: '+name)
    return results
def test_image(args):
    if args.test_image:return args.test_image.resolve()
    candidates=list(pathlib.Path('.build').glob('*/debug/AdaptivePlotterPackageTests.xctest/Contents/MacOS/AdaptivePlotterPackageTests'))
    require(len(candidates)==1,'supply exact --test-image');return candidates[0].resolve()
def source_hashes():
    paths=list(pathlib.Path('Sources').rglob('*.swift'))+list(pathlib.Path('Tests').rglob('*.swift'))
    paths+=list(pathlib.Path('Tools/DrawingExchange').glob('*.py'))+list(HERE.rglob('*'))
    paths+=[pathlib.Path('Package.swift'),pathlib.Path('Resources/DrawingExchange/v1/schema.json')]
    normalized={str(p.resolve().relative_to(pathlib.Path.cwd().resolve())):p for p in paths if p.is_file()}
    return {name:sha(path) for name,path in sorted(normalized.items())}
def source_binding(args,expected):
    manifest_path=args.build_manifest.resolve();manifest=json.loads(manifest_path.read_text())
    require(manifest['exitCode']==0 and manifest['sourceHashesBefore']==manifest['sourceHashesAfter'],'build source observation not successful/current')
    require(manifest['testArtifact']==expected,'loaded artifact is not bound to frozen build receipt')
    current=source_hashes()
    require(current==manifest['sourceHashesAfter'],'source/driver changed since frozen build')
    require(str(pathlib.Path(__file__).resolve()).endswith('Tests/Fixtures/DrawingExchange/dx03/run.py'),'driver identity')
    return {'buildManifestPath':str(manifest_path),'buildManifestSHA256':sha(manifest_path),'sourceHashes':current,'driverSHA256':sha(pathlib.Path(__file__))}
def helper(args,directory,name,expected,*,trials,warmups,raw_read=False,controls=False):
    output=directory/(name+'.json');log=directory/(name+'.log');ack=directory/(name+'.ack.json');stage=directory/(name+'-staging');stage.mkdir();token=str(uuid.uuid4())
    command=['swift','test','--skip-build','--no-parallel','--filter','DrawingExchangeCarrierPerformanceTests']
    env={k:v for k,v in os.environ.items() if not k.startswith(('DX','LLVM_PROFILE')) and k!='PORTRAIT_REAL_PILOT_ROOT'}
    env.update(DX03_PERF_ROOT=str(args.root/'source'),DX03_PERF_OUTPUT=str(output),DX03_PERF_STAGE=str(stage),DX03_PERF_ACK=str(ack),DX03_PERF_TOKEN=token,DX03_PERF_EXPECTED_IMAGE=expected['path'],DX03_PERF_TRIALS=str(trials),DX03_PERF_WARMUPS=str(warmups))
    if raw_read:env['DX03_PERF_CONTROL']='raw-read'
    start=time.monotonic();before=metadata(args.root/'source');host={};rejections=[]
    with log.open('xb') as stream:
        process=subprocess.Popen(command,env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            deadline=time.monotonic()+min(args.timeout,120)
            while not output.exists() and process.poll()is None and time.monotonic()<deadline:time.sleep(.01)
            require(output.exists(),'helper identity receipt absent; inspect '+str(log));initial=json.loads(output.read_text());identity=initial['identity']
            host={'launcherPID':process.pid,'helperPID':identity['pid'],'ancestry':validate_identity(identity,expected,token,process.pid)}
            if controls:rejections=identity_controls(identity,expected,token,process.pid)
            write_json(ack,{'pid':identity['pid'],'token':token,'testImageSHA256':expected['sha256']})
            code=process.wait(timeout=args.timeout)
        except Exception:
            if process.poll()is None:
                import signal
                os.killpg(process.pid,signal.SIGTERM)
                try:process.wait(timeout=10)
                except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
            raise
    result=json.loads(output.read_text())
    source_unchanged=metadata(args.root/'source')==before
    receipt={'argv':command,'exitCode':code,'elapsedSeconds':time.monotonic()-start,'hostProcessObservation':host,'identityRejectionControls':rejections,
      'testArtifact':expected,'resultSHA256':sha(output),'sourceMetadataUnchanged':source_unchanged,'cache':'filesystem uncontrolled; untimed source integrity reads precede session; processwarm/fresh classified explicitly','platform':platform.platform()}
    write_json(directory/(name+'.command.json'),receipt)
    require(result['identity']==identity,'helper identity changed during run')
    require(source_unchanged,'source metadata changed during helper')
    if raw_read:
        require(code!=0 and result['status']=='rejected' and result['failure']['rawMaterializedBytes']>0 and result['failure']['rawMaterializationPasses']>0,'raw-read rejection control did not prove its cause')
        require(pathlib.Path(result['failure']['stagingPath']).exists(),'failed inspection bytes not retained')
    else:
        require(code==0 and result['status']=='complete' and len(result['trials'])==trials and len(result['warmups'])==warmups,'helper failed; inspect '+str(log))
        require(not list(stage.iterdir()),'successful staging output not cleaned')
        recipe=json.loads((args.root/'recipe.json').read_text());total=recipe['inventory']['logicalBytes']
        for row in result['trials']+result['warmups']:
            stats=row['importStatistics'];require(row['fileBytes']==total,'file inventory total mismatch')
            require(row['rawAssetCount']==recipe['frames'] and row['programCount']==1,'corpus/admission identity mismatch')
            require(sum(stats['materializedBytesByPath'].values())==stats['materializedBytesRead'],'per-path materialization accounting mismatch')
            require(all(stats[k]==total for k in ('sourceBytesRead','stagedBytesWritten','verificationBytesRead','hashedBytes')),'file copy/hash pass count mismatch')
            require(stats['imageDecodeCount']==0 and stats['imageHeaderReads']==0 and stats['programJSONDecodeCalls']==1 and stats['producerValidatorEntries']==1,'decode/validator entry counters')
            require(row['rawMaterializedBytes']==0 and row['rawMaterializationPasses']==0,'raw bytes materialized')
            exported=row['exportCounters'];verified=row['exportVerificationStatistics']
            require(exported['fileBytesRead']==total and exported['fileBytesWritten']==total,'export pass count mismatch')
            require(all(exported[k]==0 for k in ('programJSONDecodeCalls','producerValidatorEntries','imageDecodeCount','materializedBytesRead','materializationPasses')),'export decoded/materialized records or media')
            require(verified['verificationBytesRead']==total and verified['hashedBytes']==total and verified['programJSONDecodeCalls']==0 and verified['producerValidatorEntries']==0 and verified['imageHeaderReads']==0 and verified['imageDecodeCount']==0,'untimed export verification counters')
            require(row['outputByteIntegrityVerified'] is True and row['outputFileCount']==row['fileCount'],'preserved output identity')
    return result

def percentile(values,p):return sorted(values)[math.ceil(p*len(values))-1]
def measure(args):
    destination=args.root/args.label;destination.mkdir(exist_ok=False);expected=artifact(test_image(args));source_before=source_binding(args,expected);write_json(destination/'build-source-before.json',source_before);before=inventory(args.root/'source');write_json(destination/'source-before.json',before)
    require(before==json.loads((args.root/'recipe.json').read_text())['inventory'],'prepared source inventory drifted')
    results=[]
    if args.mode=='process-warm':results.append(helper(args,destination,'warm-helper',expected,trials=30,warmups=1))
    else:
        for n in range(5):results.append(helper(args,destination,f'fresh-helper-{n}',expected,trials=1,warmups=0))
    after=inventory(args.root/'source');require(after==before,'source bytes changed');write_json(destination/'source-after.json',after)
    require(artifact(test_image(args))==expected,'test artifact changed')
    source_after=source_binding(args,expected);require(source_after==source_before,'source/driver changed during measurement');write_json(destination/'build-source-after.json',source_after)
    times=[row['importMilliseconds'] for result in results for row in result['trials']];exports=[row['exportMilliseconds'] for result in results for row in result['trials']]
    write_json(destination/'summary.json',{'schemaVersion':2,'mode':args.mode,'operationCount':len(times),'helperCount':len(results),'importMilliseconds':times,'exportMilliseconds':exports,'importP50Milliseconds':percentile(times,.5),'importP95Milliseconds':percentile(times,.95),'exportP50Milliseconds':percentile(exports,.5),'exportP95Milliseconds':percentile(exports,.95),'percentileMethod':'nearest rank',
      'helperLifetimePeakRSSBytes':[max(row['processPeakRSSBytes'] for row in r['warmups']+r['trials']) for r in results],
      'memoryScope':'Actual helper process lifetime highwater includes import+export+untimed output verification; warmhelper30samples share cumulativepeak, not independent phase/trial allocations',
      'cache':'Filesystem cache uncontrolled; untimed full-source integrity read precedes session; no coldfilesystem claim','evidenceClass':'synthetic inert software carrier import+directory preservation; no library publication/optimization/nativeUI/physicalclaim',
      'sourceInventorySHA256':sha(destination/'source-before.json'),'testArtifact':expected,'driverSHA256':sha(pathlib.Path(__file__)),
      'readerSHA256':{str(p):sha(p) for p in sorted(pathlib.Path('Sources/PortraitCore').glob('DrawingExchange*.swift'))}})
def control(args):
    destination=args.root/args.label;destination.mkdir(exist_ok=False);expected=artifact(test_image(args));source_before=source_binding(args,expected);write_json(destination/'build-source-before.json',source_before);before=inventory(args.root/'source');write_json(destination/'source-before.json',before)
    normal=helper(args,destination,'tiny-proof',expected,trials=1,warmups=1,controls=True)
    rejected=helper(args,destination,'nonzero-raw-read',expected,trials=1,warmups=0,raw_read=True)
    require(inventory(args.root/'source')==before,'control source changed');require(artifact(test_image(args))==expected,'test artifact changed')
    source_after=source_binding(args,expected);require(source_after==source_before,'source/driver changed during control');write_json(destination/'build-source-after.json',source_after)
    write_json(destination/'control-summary.json',{'identityControls':'all9wrong/stale wrapper/helper PID/argv/executable/token/image controls rejected before operations','normalProof':'oneexcludedwarmup+onecompleted fullimport/export with exact untimed output SHA proof','rawReadControl':'real nonzero rawfile materialization rejected; failed staging preserved','testArtifact':expected,'normalPID':normal['identity']['pid'],'negativePID':rejected['identity']['pid'],'driverSHA256':sha(pathlib.Path(__file__))})
if __name__=='__main__':
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='action',required=True)
    prep=sub.add_parser('prepare');prep.add_argument('--root',type=pathlib.Path,required=True);prep.add_argument('--frames',type=int,default=640);prep.add_argument('--frame-bytes',type=int);prep.add_argument('--width',type=int,default=4096);prep.add_argument('--height',type=int,default=4096)
    for action in ('measure','control'):
        run=sub.add_parser(action);run.add_argument('--root',type=pathlib.Path,required=True);run.add_argument('--label',required=True);run.add_argument('--test-image',type=pathlib.Path);run.add_argument('--timeout',type=int,default=3600);run.add_argument('--build-manifest',type=pathlib.Path,required=True)
        if action=='measure':run.add_argument('--mode',choices=['process-warm','process-fresh'],required=True)
    args=parser.parse_args();args.root=args.root.resolve();globals()[args.action](args)
