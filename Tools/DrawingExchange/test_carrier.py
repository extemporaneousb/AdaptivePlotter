"""Carrier attacks use throwaway bags; frozen vectors are never rewritten."""
import copy
import json
import os
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
import zipfile
import zlib
from carrier import BAGIT, Limits, UnsupportedFormat, import_carrier
from reader import parse, sha256

FIXTURE=Path(__file__).resolve().parents[2]/'Tests/Fixtures/DrawingExchange/v1/source-free.zip'

class CarrierTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.stage=self.root/'staging';self.stage.mkdir()
        self.bag=self.root/'bag';self.bag.mkdir()
        with zipfile.ZipFile(FIXTURE) as archive:
            for entry in archive.infolist():
                target=self.bag/entry.filename;target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(archive.read(entry))
    def manifests(self):
        payload=[];tags=[]
        for path in sorted(self.bag.rglob('*')):
            if not path.is_file() or path.name in ('manifest-sha256.txt','tagmanifest-sha256.txt'):continue
            name=path.relative_to(self.bag).as_posix()
            (payload if name.startswith('data/') else tags).append((name,sha256(path.read_bytes())))
        def lines(entries):return ''.join(d+'  '+p+'\n' for p,d in entries).encode()
        manifest=lines(payload);(self.bag/'manifest-sha256.txt').write_bytes(manifest)
        tags.append(('manifest-sha256.txt',sha256(manifest)))
        (self.bag/'tagmanifest-sha256.txt').write_bytes(lines(tags))
    def zip(self, entries=None, compression=zipfile.ZIP_DEFLATED):
        target=self.root/'test.zip'
        with zipfile.ZipFile(target,'w',compression=compression) as archive:
            for path in sorted(self.bag.rglob('*')):
                if path.is_file():archive.write(path,path.relative_to(self.bag).as_posix())
            for name,data in entries or []:archive.writestr(name,data)
        return target
    def reject(self, source=None, **kwargs):
        with self.assertRaises((ValueError,OSError,zipfile.BadZipFile)) as caught:
            import_carrier(source or self.bag,self.stage,**kwargs)
        self.assertTrue(caught.exception.staging.exists())
        self.assertTrue(self.bag.exists())
        return caught.exception
    def index(self):return parse((self.bag/'data/exchange.json').read_bytes())
    def put_index(self,index):
        (self.bag/'data/exchange.json').write_bytes(json.dumps(index,separators=(',',':')).encode());self.manifests()
    def test_empty_machine_zip_directory_parity_and_apcb(self):
        a=import_carrier(FIXTURE,self.stage);b=import_carrier(self.bag,self.stage)
        self.assertEqual(a.index,b.index);self.assertEqual(a.drawings,b.drawings)
        self.assertTrue(a.drawings[0]['producerVerified']);self.assertFalse(a.drawings[0]['blocked'])
        with zipfile.ZipFile(FIXTURE) as archive:
            for path in archive.namelist():self.assertEqual((a.staging/path).read_bytes(),archive.read(path))
        self.assertEqual((a.staging/'incoming.zip').read_bytes(),FIXTURE.read_bytes())
    def test_bagit_exact_two_lf(self):
        for raw in (BAGIT.replace(b'\n',b'\r\n'),BAGIT+b'\n',b'\xef\xbb\xbf'+BAGIT):
            (self.bag/'bagit.txt').write_bytes(raw);self.manifests();self.reject()
    def test_manifest_closure_and_hash(self):
        (self.bag/'data/unlisted').write_bytes(b'x');self.reject()
        self.manifests();(self.bag/'data/unlisted').write_bytes(b'y');self.reject()
    def test_fetch_and_missing_manifest(self):
        (self.bag/'fetch.txt').write_bytes(b'');self.manifests();self.reject()
        (self.bag/'fetch.txt').unlink();(self.bag/'tagmanifest-sha256.txt').unlink();self.reject()
    def test_duplicate_manifest_line(self):
        path=self.bag/'manifest-sha256.txt';raw=path.read_bytes();path.write_bytes(raw+raw.splitlines(keepends=True)[0]);self.reject()
    def test_tag_manifest_cannot_list_payload_or_self(self):
        path=self.bag/'tagmanifest-sha256.txt'
        path.write_bytes(path.read_bytes()+sha256(b'') .encode()+b'  tagmanifest-sha256.txt\n');self.reject()
    def test_symlink_hardlink_and_special(self):
        source=self.bag/'bagit.txt';link=self.bag/'link';link.symlink_to(source);self.reject();link.unlink()
        os.link(source,link);self.reject();link.unlink()
        os.mkfifo(link);self.reject()
    def require_case_sensitive_volume(self):
        probe=self.root/'caseprobe';probe.write_bytes(b'probe')
        if (self.root/'CASEPROBE').exists():
            self.skipTest('Directory case aliases cannot coexist on this case-insensitive volume; portable ZIP collision controls run separately')
    def test_case_collision_in_directory(self):
        self.require_case_sensitive_volume()
        (self.bag/'BAGIT.TXT').write_bytes(BAGIT);self.reject()
    def test_component_case_aliases(self):
        self.require_case_sensitive_volume()
        (self.bag/'Foo').mkdir();(self.bag/'Foo/a').write_bytes(b'a')
        (self.bag/'foo').mkdir();(self.bag/'foo/b').write_bytes(b'b');self.reject()
    def coherently_manifested_zip(self,extra):
        files={p.relative_to(self.bag).as_posix():p.read_bytes() for p in self.bag.rglob('*') if p.is_file()}
        files.update(extra)
        def manifest(paths):return ''.join(sha256(files[p])+'  '+p+'\n' for p in sorted(paths)).encode()
        files['manifest-sha256.txt']=manifest(p for p in files if p.startswith('data/'))
        files['tagmanifest-sha256.txt']=manifest(p for p in files if not p.startswith('data/') and p!='tagmanifest-sha256.txt')
        target=self.root/'coherent.zip'
        with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED) as archive:
            for name,data in files.items():archive.writestr(name,data)
        return target
    def test_coherent_zip_case_collision_is_refused_on_every_host(self):
        target=self.coherently_manifested_zip({'data/Case':b'a','data/case':b'b'})
        self.assertIn('collision',str(self.reject(target)))
    def test_coherent_zip_component_case_collision_on_every_host(self):
        target=self.coherently_manifested_zip({'data/Foo/a':b'a','data/foo/b':b'b'})
        self.assertIn('collision',str(self.reject(target)))
    def test_unsafe_zip_paths_and_duplicates(self):
        for name in ('../escape','/absolute','data\\escape','data/../escape','data/a:b','data/a\x01b','data/e\u0301','BAGIT.TXT','bagit.txt'):
            self.reject(self.zip([(name,b'x')]))
            self.assertFalse((self.root/'escape').exists())
    def test_zip_symlink(self):
        target=self.root/'link.zip'
        with zipfile.ZipFile(target,'w') as archive:
            info=zipfile.ZipInfo('link');info.create_system=3;info.external_attr=(0o120777<<16);archive.writestr(info,b'outside')
        self.reject(target)
    def test_zip_local_metadata_disagreement(self):
        target=self.zip();raw=bytearray(target.read_bytes());struct.pack_into('<I',raw,22,1);target.write_bytes(raw);self.reject(target)
    def test_zip_local_central_time_and_date_disagreement(self):
        for offset in (10,12):
            target=self.zip();raw=bytearray(target.read_bytes());raw[offset]^=1;target.write_bytes(raw);self.reject(target)
    def test_zip_empty_stored_and_deflated_directories(self):
        for method in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED):
            target=self.zip([('empty/',b'')],compression=method)
            result=import_carrier(target,self.stage)
            self.assertTrue((result.staging/'empty').is_dir())
    def test_zip_empty_directory_crc_is_checked(self):
        for method in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED):
            target=self.zip([('empty/',b'')],compression=method);raw=bytearray(target.read_bytes())
            position=raw.index(b'empty/')-30;struct.pack_into('<I',raw,position+14,1)
            central=raw.index(b'PK\x01\x02');found=False
            while raw[central:central+4]==b'PK\x01\x02':
                nl,xl,cl=struct.unpack_from('<HHH',raw,central+28)
                if raw[central+46:central+46+nl]==b'empty/':
                    struct.pack_into('<I',raw,central+16,1);found=True;break
                central+=46+nl+xl+cl
            self.assertTrue(found);target.write_bytes(raw);self.reject(target)
    def test_zip_deflated_directory_stream_is_checked(self):
        target=self.zip([('empty/',b'')]);raw=bytearray(target.read_bytes())
        position=raw.index(b'empty/')-30;nl,xl=struct.unpack_from('<HH',raw,position+26)
        raw[position+30+nl+xl]^=255;target.write_bytes(raw);self.reject(target)
    def test_zip_prefix_truncation_trailing_data(self):
        original=self.zip().read_bytes()
        for raw in (b'x'+original,original[:-1],original+b'x'):
            target=self.root/'broken.zip';target.write_bytes(raw);self.reject(target)
    def test_zip_unsupported_method_flags_and_zip64(self):
        for offset,value in ((8,12),(6,8)):
            target=self.zip();raw=bytearray(target.read_bytes());struct.pack_into('<H',raw,offset,value);target.write_bytes(raw)
            self.reject(target)
        target=self.root/'zip64.zip'
        with zipfile.ZipFile(target,'w') as archive:
            with archive.open('large','w',force_zip64=True) as out:out.write(b'x')
        self.reject(target)
    def test_zip_crc_corruption(self):
        target=self.zip(compression=zipfile.ZIP_STORED);raw=bytearray(target.read_bytes());n,x=struct.unpack_from('<HH',raw,26);raw[30+n+x]^=1;target.write_bytes(raw);self.reject(target)
    def test_expansion_and_total_limits(self):
        self.reject(self.zip(),limits=Limits(expansion_ratio=1))
        self.reject(limits=Limits(total_bytes=100))
        self.reject(limits=Limits(entries=2))
        self.reject(limits=Limits(record_bytes=10))
    def test_descriptor_length_hash_coherent_forgery(self):
        index=self.index();index['assets'][0]['byteLength']+=1;self.put_index(index);self.reject()
    def test_missing_claimed_asset(self):
        index=self.index();digest=index['assets'][0]['object'];(self.bag/'data/objects/sha256'/digest).unlink();self.manifests();self.reject()
    def test_unknown_exchange_feature_blocks_capabilities_preserves_bytes(self):
        index=self.index();index['requiredFeatures']=['future.required'];self.put_index(index)
        result=import_carrier(self.bag,self.stage)
        self.assertTrue(result.drawings[0]['blocked']);self.assertFalse(any(result.drawings[0]['capabilities'].values()))
        self.assertEqual((result.staging/'data/exchange.json').read_bytes(),(self.bag/'data/exchange.json').read_bytes())
    def test_unknown_exchange_major_is_opaque(self):
        index=self.index();index['profile']='adaptiveplotter.exchange/2';self.put_index(index)
        result=import_carrier(self.bag,self.stage);self.assertEqual(result.drawings,[]);self.assertTrue(result.unsupported)
    def test_unknown_representation_is_opaque(self):
        index=self.index();ref=index['roots'][0]
        path=self.bag/f"data/drawings/{ref['issuer']}/{ref['revision']}/drawing.json"
        record=parse(path.read_bytes());record['representation']['kind']='future.vector/1';raw=json.dumps(record).encode();path.write_bytes(raw)
        ref['digest']=sha256(raw);self.put_index(index)
        result=import_carrier(self.bag,self.stage);self.assertTrue(result.drawings[0]['opaque'])
    def test_cancellation_fault_keep_original_and_staging(self):
        before=FIXTURE.read_bytes()
        with self.assertRaises(InterruptedError) as caught:import_carrier(FIXTURE,self.stage,cancelled=lambda:True)
        self.assertEqual((caught.exception.staging/'incoming.zip').read_bytes(),before)
        def fault(name,size):raise RuntimeError('injected write failure')
        with self.assertRaises(RuntimeError) as caught:import_carrier(FIXTURE,self.stage,fault=fault)
        self.assertEqual((caught.exception.staging/'incoming.zip').read_bytes(),before)
        self.assertEqual(FIXTURE.read_bytes(),before)
    def add_asset(self,raw,**metadata):
        index=self.index();d={'object':sha256(raw),'byteLength':len(raw),**metadata}
        (self.bag/'data/objects/sha256'/d['object']).write_bytes(raw);index['assets'].append(d);self.put_index(index)
        return d
    def test_raw_and_array_metadata_length_dimension_overflow(self):
        d=self.add_asset(b'1234',mediaType='application/octet-stream',encoding='raw-gray8',pixelLayout={
            'width':2,'height':2,'pixelFormat':'gray','componentType':'uint8','bitDepth':8,
            'channelOrder':['gray'],'rowStride':2,'byteOrder':'not-applicable','orientation':'up','colorInterpretation':'linear-gray'})
        import_carrier(self.bag,self.stage)
        index=self.index();index['assets'][-1]['pixelLayout']['rowStride']=3;self.put_index(index);self.reject()
        index['assets'][-1]['encoding']='array-float32';index['assets'][-1].pop('pixelLayout')
        index['assets'][-1]['arrayLayout']={'shape':[9007199254740991,2],'dtype':'float32','layout':'row-major','byteOrder':'little','units':'field'}
        self.put_index(index);self.reject()
    def test_png_actual_header_dimensions_crc_type_and_truncation(self):
        def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
        raw=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,0,0,0,0))+chunk(b'IDAT',zlib.compress(b'\x00\x80'))+chunk(b'IEND',b'')
        self.add_asset(raw,mediaType='image/png',encoding='png',dimensions={'width':2,'height':1})
        self.reject()
        index=self.index();index['assets'][-1]['dimensions']['width']=1;self.put_index(index);import_carrier(self.bag,self.stage)
        index['assets'][-1]['mediaType']='image/jpeg';self.put_index(index);self.reject()
    def test_png_critical_chunk_crc_hash_coherent_forgery(self):
        def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
        raw=bytearray(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,0,0,0,0))+chunk(b'IDAT',zlib.compress(b'\x00\x80'))+chunk(b'IEND',b''))
        raw[29]^=1
        self.add_asset(bytes(raw),mediaType='image/png',encoding='png',dimensions={'width':1,'height':1});self.reject()
    def test_known_raw_channel_order_contradiction(self):
        self.add_asset(b'123',mediaType='application/octet-stream',encoding='raw-rgb8',pixelLayout={
            'width':1,'height':1,'pixelFormat':'rgb','componentType':'uint8','bitDepth':8,
            'channelOrder':['blue','green','red'],'rowStride':3,'byteOrder':'not-applicable','orientation':'up','colorInterpretation':'sRGB'})
        self.reject()
    def test_reopen_parent_symlink_is_refused(self):
        result=import_carrier(FIXTURE,self.stage);digest=result.index['assets'][0]['object']
        objects=result.staging/'data/objects';moved=result.staging/'other';objects.rename(moved);objects.symlink_to(moved,target_is_directory=True)
        with self.assertRaises(OSError):result.store.read_object(digest,1024**2)
    def test_wrong_record_type_with_coherent_hash(self):
        index=self.index();ref=index['roots'][0];path=self.bag/f"data/drawings/{ref['issuer']}/{ref['revision']}/drawing.json"
        value=parse(path.read_bytes());value['profile']='adaptiveplotter.photo/1';raw=json.dumps(value).encode();path.write_bytes(raw)
        ref['digest']=sha256(raw);self.put_index(index);self.reject()
    def test_manifest_unsafe_path_even_with_matching_digest(self):
        path=self.bag/'manifest-sha256.txt';path.write_bytes(path.read_bytes()+sha256(b'x').encode()+b'  data/../x\n');self.reject()
    def result_bag(self, *, refused=False, change=None, coverage_change=None):
        uid='11111111-1111-4111-8111-111111111111';run='22222222-2222-4222-8222-222222222222'
        index=self.index();index['kind']='result';drawing=index['roots'][0]
        def obj(value,encoding):
            raw=json.dumps(value,separators=(',',':')).encode();d=sha256(raw)
            (self.bag/'data/objects/sha256'/d).write_bytes(raw)
            index['assets'].append({'object':d,'byteLength':len(raw),'mediaType':'application/json','encoding':encoding})
            return d
        intent=obj({'profile':'fixture.intent/1'},'fixture.intent/1')
        coverage_value=({'profile':'adaptiveplotter.coverage/1','requiredFeatures':[],
            'includedAsOf':{'wallTime':'2026-11-03T18:00:00Z'},'entries':[],
            'frontiers':{k:{'kind':'fixture.frontier/'+k,'status':'unavailable','reason':'not supported'} for k in ('planned','commanded','controllerCompleted','inkVerified')}})
        if coverage_change:coverage_change(coverage_value)
        coverage=obj(coverage_value,'adaptiveplotter.coverage/1')
        descriptor=index['assets'][-2]
        receipt={'profile':'adaptiveplotter.plot-job-receipt/1','requiredFeatures':[],
            'handle':{'engine':uid,'job':uid},'client':{'namespace':uid,'request':uid,'requestDigest':'a'*64},
            'drawing':drawing,'preparedPlan':descriptor,'requestedMediumOptions':descriptor,
            'issuedAt':{'wallTime':'2026-11-03T18:00:00Z'},'disposition':'refused' if refused else 'accepted','reason':'fixture'}
        if not refused:receipt['issuance']=uid
        if change:change('receipt',receipt)
        raw=json.dumps(receipt).encode();job={'engine':uid,'job':uid,'receiptDigest':sha256(raw)}
        path=self.bag/f'data/jobs/{uid}/{uid}/receipt.json';path.parent.mkdir(parents=True);path.write_bytes(raw);index['jobs']=[job]
        previous=None
        if not refused:
            for sequence in (1,2):
                record={'profile':'adaptiveplotter.plot-attempt/1','requiredFeatures':[],'issuerArchive':uid,'run':run,
                    'sequence':sequence,'previous':previous,'sealed':sequence==2,'drawing':drawing,'job':job,
                    'environment':'simulation','intent':intent,'coverage':coverage,'state':'interrupted',
                    'dispatch':'possibleInk','observation':'unavailable','terminalRecord':None,'assessments':[]}
                if change:change(sequence,record)
                raw=json.dumps(record).encode();previous=sha256(raw)
                path=self.bag/f'data/attempts/{uid}/{run}/{sequence}/attempt.json';path.parent.mkdir(parents=True);path.write_bytes(raw)
            index['attempts']=[{'archive':uid,'run':run,'sequence':2,'digest':previous}]
        self.put_index(index)
        return uid,run
    def test_closed_chain_predecessor_loaded_and_native_semantics_blocked(self):
        self.result_bag();result=import_carrier(self.bag,self.stage)
        self.assertIn('native intent/coverage/frontier semantics unsupported',result.unsupported)
        self.assertTrue(result.drawings[0]['capabilities']['preview'])
    def test_refused_zero_attempt_result(self):
        self.result_bag(refused=True);result=import_carrier(self.bag,self.stage);self.assertEqual(result.index['attempts'],[])
    def test_accepted_zero_attempt_result_rejected(self):
        def accept(n,value):
            if n=='receipt':
                value['disposition']='accepted';value['issuance']='11111111-1111-4111-8111-111111111111'
        self.result_bag(refused=True,change=accept);self.reject()
    def test_accepted_zero_attempt_drawing_package_preserved(self):
        def accept(n,value):
            if n=='receipt':
                value['disposition']='accepted';value['issuance']='11111111-1111-4111-8111-111111111111'
        self.result_bag(refused=True,change=accept);index=self.index();index['kind']='drawing';self.put_index(index)
        result=import_carrier(self.bag,self.stage);self.assertEqual(result.index['attempts'],[])
    def test_unknown_disposition_zero_attempt_result_is_opaque(self):
        self.result_bag(refused=True,change=lambda n,v:v.update(disposition='future-held') if n=='receipt' else None)
        result=import_carrier(self.bag,self.stage)
        self.assertEqual(result.index['attempts'],[]);self.assertIn('unsupported job disposition',result.unsupported)
    def test_unknown_major_minimal_index_needs_no_v1_fields(self):
        index={'profile':'adaptiveplotter.exchange/9','futureBody':{'opaque':[1,2,3]}}
        self.put_index(index);raw=(self.bag/'data/exchange.json').read_bytes()
        result=import_carrier(self.bag,self.stage)
        self.assertEqual(result.drawings,[]);self.assertTrue(result.unsupported)
        self.assertEqual((result.staging/'data/exchange.json').read_bytes(),raw)
    def test_chain_missing_predecessor(self):
        uid,run=self.result_bag();(self.bag/f'data/attempts/{uid}/{run}/1/attempt.json').unlink();self.manifests();self.reject()
    def test_hash_coherent_chain_possible_ink_reversion(self):
        self.result_bag(change=lambda n,r:r.update(dispatch='not-dispatched') if n==2 else None);self.reject()
    def test_hash_coherent_post_seal_continuation(self):
        self.result_bag(change=lambda n,r:r.update(sealed=True) if n==1 else None);self.reject()
    def test_refused_issuance_rejected(self):
        self.result_bag(refused=True,change=lambda n,r:r.update(issuance='11111111-1111-4111-8111-111111111111') if n=='receipt' else None);self.reject()
    def test_unknown_disposition_with_attempt_retains_inert_exact_bytes(self):
        def future(n,value):
            if n=='receipt':
                value['disposition']='future-held';value.pop('issuance',None)
        uid,run=self.result_bag(change=future)
        result=import_carrier(self.bag,self.stage)
        self.assertIn('unsupported job disposition',result.unsupported)
        self.assertIn('native intent/coverage/frontier semantics unsupported',result.unsupported)
        self.assertFalse(result.drawings[0]['capabilities']['train'])
        for source in self.bag.rglob('*'):
            if source.is_file():self.assertEqual(source.read_bytes(),(result.staging/source.relative_to(self.bag)).read_bytes())
        job=result.index['jobs'][0]
        receipt=parse(result.store.read_object(job['receiptDigest']))
        self.assertEqual(receipt['disposition'],'future-held');self.assertNotIn('issuance',receipt)
    def test_known_refusal_with_linked_attempt_is_rejected(self):
        def refuse(n,value):
            if n=='receipt':value['disposition']='refused';value.pop('issuance',None)
        self.result_bag(change=refuse);self.reject()
    def test_wrong_predecessor_digest(self):
        self.result_bag(change=lambda n,r:r.update(previous='0'*64) if n==2 else None);self.reject()
    def add_assessment(self,change=None):
        index=self.index();uid='33333333-3333-4333-8333-333333333333'
        value={'profile':'adaptiveplotter.assessment/1','requiredFeatures':[],'ref':{'issuer':uid,'revision':uid},
            'targets':[{'kind':'drawing','ref':copy.deepcopy(index['roots'][0])}],
            'reviewer':{'kind':'human','id':'fixture-reviewer'},'time':{'wallTime':'2026-11-03T18:00:00Z'},
            'question':{'id':'fixture.question','version':'1','text':'fixture question'},
            'answer':{'type':'fixture.answer','value':True},'supportingAssets':[]}
        if change:change(value,index)
        raw=json.dumps(value).encode();path=self.bag/f'data/assessments/{uid}/{uid}.json';path.parent.mkdir(parents=True);path.write_bytes(raw)
        index['assessments']=[{'issuer':uid,'revision':uid,'digest':sha256(raw)}];self.put_index(index)
        return raw
    def test_required_job_reason_missing(self):
        self.result_bag(change=lambda n,v:v.pop('reason') if n=='receipt' else None);self.reject()
    def test_required_job_reason_null(self):
        self.result_bag(change=lambda n,v:v.update(reason=None) if n=='receipt' else None);self.reject()
    def test_attempt_boolean_sequence_rejected(self):
        self.result_bag(change=lambda n,v:v.update(sequence=True) if n==1 else None);self.reject()
    def test_boolean_disposition_is_not_unknown_enum(self):
        self.result_bag(change=lambda n,v:v.update(disposition=True) if n=='receipt' else None);self.reject()
    def test_null_attempt_enum_is_not_unknown(self):
        self.result_bag(change=lambda n,v:v.update(observation=None) if n==2 else None);self.reject()
    def test_index_required_and_container_scalar_types(self):
        original=self.index()
        for field,bad in (('kind',True),('roots',None),('assets',{}),('assessments',False)):
            index=copy.deepcopy(original);index[field]=bad;self.put_index(index);self.reject()
        index=copy.deepcopy(original);index.pop('attempts');self.put_index(index);self.reject()
    def test_assessment_missing_question_rejected(self):
        self.add_assessment(lambda v,i:v.pop('question'));self.reject()
    def test_reviewer_nonstring_id_rejected(self):
        self.add_assessment(lambda v,i:v['reviewer'].update(id=1));self.reject()
    def test_reviewer_boolean_kind_rejected(self):
        self.add_assessment(lambda v,i:v['reviewer'].update(kind=True));self.reject()
    def test_unknown_reviewer_with_known_refs_preserved(self):
        def future(value,index):
            value['reviewer']['kind']='future-reviewer';value['supportingAssets']=[index['assets'][0]]
        raw=self.add_assessment(future);result=import_carrier(self.bag,self.stage)
        self.assertIn('unsupported reviewer kind',result.unsupported)
        self.assertEqual(result.store.read_object(result.index['assessments'][0]['digest']),raw)
    def test_unknown_reviewer_dangling_known_asset_rejected(self):
        def future(value,index):
            value['reviewer']['kind']='future-reviewer';d=copy.deepcopy(index['assets'][0]);d['object']='0'*64;value['supportingAssets']=[d]
        self.add_assessment(future);self.reject()
    def test_unknown_reviewer_dangling_known_target_rejected(self):
        def future(value,index):
            value['reviewer']['kind']='future-reviewer';value['targets'][0]['ref']['digest']='0'*64
        self.add_assessment(future);self.reject()
    def test_unknown_target_body_is_opaque(self):
        def future(value,index):
            value['targets'].append({'kind':'future-target','body':{'object':'0'*64,'encoding':'future.type/1'}})
        self.add_assessment(future);result=import_carrier(self.bag,self.stage)
        self.assertIn('unsupported assessment target',result.unsupported)
    def test_coverage_optional_vendor_metadata_preserved(self):
        extra={'vendor.note':True,'vendor.metadata':{'object':'0'*64,'encoding':'unknown.type/1'}}
        self.result_bag(coverage_change=lambda v:v['frontiers'].update(extra))
        result=import_carrier(self.bag,self.stage);ref=result.index['attempts'][0]
        snapshot=parse(result.store.read_object(ref['digest']));raw=result.store.read_object(snapshot['coverage'])
        self.assertEqual(parse(raw)['frontiers']['vendor.metadata'],extra['vendor.metadata'])
        self.assertEqual(raw,(self.bag/'data/objects/sha256'/snapshot['coverage']).read_bytes())
    def test_coverage_unknown_status_known_asset_still_validated(self):
        def future(value):
            value['frontiers']['planned'].update(status='future-status',asset={'object':'0'*64,'byteLength':1,'encoding':'fixture.raw/1','mediaType':'application/octet-stream'})
        self.result_bag(coverage_change=future);self.reject()
    def test_coverage_boolean_status_rejected(self):
        self.result_bag(coverage_change=lambda v:v['frontiers']['planned'].update(status=True));self.reject()
    def add_ranking(self,change=None):
        index=self.index();uid='44444444-4444-4444-8444-444444444444'
        ids=['55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666']
        p={'id':'fixture.producer','version':'1','record':index['assets'][1]['object']}
        value={'profile':'adaptiveplotter.feature-ranking/1','requiredFeatures':[],'ref':{'issuer':uid,'revision':uid},
            'geometry':'omitted','createdAt':{'wallTime':'2026-11-03T18:00:00Z'},
            'presentations':[{'id':i,'features':copy.deepcopy(index['assets'][0]),'producer':copy.deepcopy(p),'extractor':copy.deepcopy(p)} for i in ids],
            'question':{'id':'fixture.question','version':'1','text':'rank'},'reviewer':{'kind':'human','id':'fixture-reviewer'},
            'response':{'kind':'ranking','groups':[[i] for i in ids]},
            'limitations':'Features only; no geometry re-extraction or arbitrary future image labels.'}
        if change:change(value,index)
        raw=json.dumps(value).encode();path=self.bag/f'data/rankings/{uid}/{uid}.json';path.parent.mkdir(parents=True);path.write_bytes(raw)
        index['rankingCapsules']=[{'issuer':uid,'revision':uid,'digest':sha256(raw)}];self.put_index(index)
        return raw
    def test_ranking_missing_producer_version_rejected(self):
        self.add_ranking(lambda v,i:v['presentations'][0]['producer'].pop('version'));self.reject()
    def test_ranking_null_question_text_rejected(self):
        self.add_ranking(lambda v,i:v['question'].update(text=None));self.reject()
    def test_ranking_boolean_response_kind_rejected(self):
        self.add_ranking(lambda v,i:v['response'].update(kind=True));self.reject()
    def test_ranking_unknown_response_with_known_features_preserved(self):
        def future(value,index):value['response']={'kind':'future-ranking','body':{'object':'0'*64,'encoding':'opaque.feature/1'}}
        raw=self.add_ranking(future);result=import_carrier(self.bag,self.stage)
        self.assertIn('unsupported ranking response',result.unsupported)
        self.assertEqual(result.store.read_object(result.index['rankingCapsules'][0]['digest']),raw)
    def test_ranking_unknown_response_dangling_known_feature_rejected(self):
        def future(value,index):
            value['response']={'kind':'future-ranking','body':{'object':'0'*64,'encoding':'opaque.feature/1'}}
            value['presentations'][0]['features']['object']='0'*64
        self.add_ranking(future);self.reject()
    def test_human_reviewer_optional_version_scalar_rejected(self):
        self.add_assessment(lambda v,i:v['reviewer'].update(version=False));self.reject()
    def test_unknown_reviewer_optional_version_empty_rejected(self):
        self.add_assessment(lambda v,i:v['reviewer'].update(kind='future-reviewer',version=''));self.reject()
    def test_present_evidence_optional_source_scalar_rejected(self):
        def bad(value):value['frontiers']['planned'].update(source=1)
        self.result_bag(coverage_change=bad);self.reject()
    def test_coverage_unknown_status_known_asset_preserved(self):
        existing=self.index()['assets'][0]
        def future(value):value['frontiers']['planned'].update(status='future-status',asset=existing)
        self.result_bag(coverage_change=future);result=import_carrier(self.bag,self.stage)
        self.assertIn('unsupported evidence status',result.unsupported)
    def test_duplicate_identical_index_refs_and_descriptors_are_idempotent(self):
        index=self.index();index['roots'].append(copy.deepcopy(index['roots'][0]));index['assets'].append(copy.deepcopy(index['assets'][0]));self.put_index(index)
        raw=(self.bag/'data/exchange.json').read_bytes();result=import_carrier(self.bag,self.stage)
        self.assertEqual(len(result.drawings),1)
        self.assertEqual(result.index,index);self.assertEqual((result.staging/'data/exchange.json').read_bytes(),raw)
    def test_duplicate_index_identity_with_conflicting_digest_rejected(self):
        index=self.index();ref=copy.deepcopy(index['roots'][0]);ref['digest']='0'*64;index['roots'].append(ref);self.put_index(index);self.reject()
    def test_duplicate_asset_with_conflicting_known_descriptor_fact_rejected(self):
        index=self.index();descriptor=copy.deepcopy(index['assets'][0]);descriptor['encoding']='different.encoding/1';index['assets'].append(descriptor);self.put_index(index);self.reject()
    def test_duplicate_descriptors_ignore_nested_vendor_only_differences(self):
        descriptor=self.add_asset(b'1234',mediaType='application/octet-stream',encoding='raw-gray8',
            dimensions={'width':2,'height':2,'vendor.dimension':'first'},
            pixelLayout={'width':2,'height':2,'pixelFormat':'gray','componentType':'uint8','bitDepth':8,
                'channelOrder':['gray'],'rowStride':2,'byteOrder':'not-applicable','orientation':'up','colorInterpretation':'linear-gray','vendor.pixel':'first'},
            arrayLayout={'shape':[4],'dtype':'uint8','layout':'row-major','byteOrder':'not-applicable','units':'field','vendor.array':'first'},
            decodedDigest={'algorithm':'fixture.digest/1','value':'opaque','vendor.digest':'first'})
        index=self.index();duplicate=copy.deepcopy(descriptor);duplicate['vendor.top']='second'
        for key,field in (('dimensions','vendor.dimension'),('pixelLayout','vendor.pixel'),('arrayLayout','vendor.array'),('decodedDigest','vendor.digest')):
            duplicate[key][field]='second'
        index['assets'].append(duplicate);self.put_index(index);raw=(self.bag/'data/exchange.json').read_bytes()
        result=import_carrier(self.bag,self.stage)
        self.assertEqual(result.index,index);self.assertEqual((result.staging/'data/exchange.json').read_bytes(),raw)
    def test_duplicate_descriptor_optional_known_presence_is_not_enriched(self):
        index=self.index();duplicate=copy.deepcopy(index['assets'][0]);duplicate['orientation']='up'
        index['assets'].append(duplicate);self.put_index(index);self.reject()
    def test_shared_ranking_and_unknown_enum_regressions(self):
        fixtures=FIXTURE.parents[1]/'dx03/closure'
        for name in ('ranking.zip','unknown-response.zip','unknown-enum.zip'):
            with self.subTest(fixture=name):
                source=fixtures/name;result=import_carrier(source,self.stage)
                with zipfile.ZipFile(source) as archive:
                    for entry in archive.infolist():
                        if not entry.is_dir():self.assertEqual((result.staging/entry.filename).read_bytes(),archive.read(entry))
                if name=='unknown-enum.zip':
                    self.assertIn('unsupported attempt dispatch',result.unsupported)
                elif name=='unknown-response.zip':self.assertIn('unsupported ranking response',result.unsupported)
    def test_capsule_without_selected_drawing_roots_validates_retained_drawing(self):
        self.add_ranking();index=self.index();index['roots']=[];index['kind']='feedback';self.put_index(index)
        result=import_carrier(self.bag,self.stage);self.assertEqual(result.drawings,[])
        self.assertTrue(any(path.startswith('data/drawings/') for path in result.store.inventory))
    def test_retained_unselected_drawing_claim_still_validated(self):
        self.add_ranking();index=self.index();root=index['roots'][0];index['roots']=[];index['kind']='feedback';self.put_index(index)
        path=self.bag/f"data/drawings/{root['issuer']}/{root['revision']}/drawing.json"
        record=parse(path.read_bytes());record['representation']['programHash']='0'*64;path.write_bytes(json.dumps(record).encode());self.manifests();self.reject()
    def test_unclaimed_noncanonical_payload_cannot_alias_admitted_record_digest(self):
        index=self.index();root=index['roots'][0]
        path=self.bag/f"data/drawings/{root['issuer']}/{root['revision']}/drawing.json"
        (self.bag/'data/unclaimed.json').write_bytes(path.read_bytes());self.manifests();self.reject()
    def test_unknown_dispatch_preserves_prior_possible_ink(self):
        self.result_bag(change=lambda n,v:v.update(dispatch='future-dispatch') if n==2 else None)
        result=import_carrier(self.bag,self.stage);self.assertIn('unsupported attempt dispatch',result.unsupported)
        ref=result.index['attempts'][0];second=parse(result.store.read_object(ref['digest']))
        first=parse(result.store.read_object(second['previous']))
        self.assertEqual(first['dispatch'],'possibleInk');self.assertEqual(second['dispatch'],'future-dispatch')
    def test_unknown_dispatch_between_possible_ink_and_known_clearance_rejects(self):
        uid,run=self.result_bag(change=lambda n,v:v.update(dispatch='future-dispatch',sealed=False) if n==2 else None)
        index=self.index();ref=index['attempts'][0]
        second_path=self.bag/f'data/attempts/{uid}/{run}/2/attempt.json';third=parse(second_path.read_bytes())
        third.update(sequence=3,previous=ref['digest'],dispatch='not-dispatched',sealed=True)
        raw=json.dumps(third).encode();path=self.bag/f'data/attempts/{uid}/{run}/3/attempt.json';path.parent.mkdir(parents=True);path.write_bytes(raw)
        index['attempts']=[{'archive':uid,'run':run,'sequence':3,'digest':sha256(raw)}];self.put_index(index);self.reject()
    @staticmethod
    def minimal_future_receipt(n,value):
        if n=='receipt':
            value.clear();value.update(profile='adaptiveplotter.plot-job-receipt/9',futureBody={'opaque':True})
    @staticmethod
    def minimal_future_predecessor(n,value):
        if n==1:
            value.clear();value.update(profile='adaptiveplotter.plot-attempt/9',futureBody={'opaque':True})
    def test_unknown_major_minimal_job_receipt_keeps_known_current_claims(self):
        self.result_bag(change=self.minimal_future_receipt);result=import_carrier(self.bag,self.stage)
        self.assertIn('unsupported job profile',result.unsupported)
        receipt=parse(result.store.read_object(result.index['jobs'][0]['receiptDigest']))
        self.assertEqual(set(receipt),{'profile','futureBody'})
        self.assertFalse(result.drawings[0]['capabilities']['train'])
    def test_unknown_major_job_does_not_hide_current_dangling_intent(self):
        def change(n,value):
            self.minimal_future_receipt(n,value)
            if n==2:value['intent']='0'*64
        self.result_bag(change=change);self.reject()
    def test_unknown_major_job_does_not_hide_current_dangling_coverage(self):
        def change(n,value):
            self.minimal_future_receipt(n,value)
            if n==2:value['coverage']='0'*64
        self.result_bag(change=change);self.reject()
    def test_unknown_major_job_does_not_hide_current_dangling_terminal(self):
        def change(n,value):
            self.minimal_future_receipt(n,value)
            if n==2:value['terminalRecord']='0'*64
        self.result_bag(change=change);self.reject()
    def test_unknown_major_job_does_not_hide_current_dangling_plan(self):
        def change(n,value):
            self.minimal_future_receipt(n,value)
            if n==2:value['plan']={'object':'0'*64,'byteLength':1,'encoding':'fixture.plan/1','mediaType':'application/json'}
        self.result_bag(change=change);self.reject()
    def test_unknown_major_job_does_not_hide_current_dangling_assessment(self):
        def change(n,value):
            self.minimal_future_receipt(n,value)
            if n==2:value['assessments']=[{'issuer':'33333333-3333-4333-8333-333333333333','revision':'33333333-3333-4333-8333-333333333333','digest':'0'*64}]
        self.result_bag(change=change);self.reject()
    def test_unknown_major_job_does_not_hide_current_dangling_drawing(self):
        def change(n,value):
            self.minimal_future_receipt(n,value)
            if n==2:value['drawing']=copy.deepcopy(value['drawing']);value['drawing']['digest']='0'*64
        self.result_bag(change=change);self.reject()
    def test_unknown_major_minimal_predecessor_preserved(self):
        self.result_bag(change=self.minimal_future_predecessor);result=import_carrier(self.bag,self.stage)
        self.assertIn('unsupported attempt profile',result.unsupported)
        ref=result.index['attempts'][0];current=parse(result.store.read_object(ref['digest']))
        previous=parse(result.store.read_object(current['previous']))
        self.assertEqual(set(previous),{'profile','futureBody'})
        self.assertEqual(current['sequence'],2)
    def test_unknown_major_predecessor_does_not_hide_current_dangling_intent(self):
        def change(n,value):
            self.minimal_future_predecessor(n,value)
            if n==2:value['intent']='0'*64
        self.result_bag(change=change);self.reject()
    def test_unknown_major_predecessor_does_not_hide_current_dangling_coverage(self):
        def change(n,value):
            self.minimal_future_predecessor(n,value)
            if n==2:value['coverage']='0'*64
        self.result_bag(change=change);self.reject()
    def test_staged_object_replacement_detected(self):
        result=import_carrier(FIXTURE,self.stage);digest=result.index['assets'][0]['object'];path=result.staging/result.store.objects[digest][0]
        raw=path.read_bytes();path.unlink();path.write_bytes(raw)
        with self.assertRaises(ValueError):result.store.read_object(digest,1024**2)

if __name__=='__main__':unittest.main()
