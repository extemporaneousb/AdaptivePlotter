import copy, json, tempfile, unittest
from pathlib import Path
from reader import drawing, parse, sha256
ROOT=Path(__file__).resolve().parents[2]/'Tests/Fixtures/DrawingExchange/dx02'
class ReaderTests(unittest.TestCase):
    def test_vectors(self):
        index=parse((ROOT/'vectors.json').read_bytes())
        for v in index['vectors']:
            result=drawing(ROOT,v['ref'])
            self.assertEqual(result['programHash'],v['programHash'])
            self.assertEqual(result['points'],v['points'])
            self.assertEqual(result['bytes'],(ROOT/'objects'/v['ref']['digest']).read_bytes())
        self.assertNotEqual(index['photos'][0],index['photos'][1])
        a,_=[parse((ROOT/'objects'/r['digest']).read_bytes()) for r in index['photos']]
        b=parse((ROOT/'objects'/index['photos'][1]['digest']).read_bytes())
        self.assertEqual(a['original'],b['original'])
    def test_strict(self):
        for raw in (b'{"a":1,"a":2}',b'{"a":NaN}',b'{"a":1e999}',b'\xef\xbb\xbf{}'):
            with self.assertRaises(ValueError): parse(raw)
    def test_corruption(self):
        index=parse((ROOT/'vectors.json').read_bytes())
        with tempfile.TemporaryDirectory() as tmp:
            target=Path(tmp);(target/'objects').mkdir()
            for f in (ROOT/'objects').iterdir(): (target/'objects'/f.name).write_bytes(f.read_bytes())
            ref=index['vectors'][0]['ref'];record=parse((target/'objects'/ref['digest']).read_bytes())
            p=target/'objects'/record['representation']['object'];p.write_bytes(b'{}')
            with self.assertRaises(ValueError): drawing(target,ref)

class SemanticTests(unittest.TestCase):
    def setUp(self):
        import shutil
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        shutil.copytree(ROOT/'objects',self.root/'objects')
        self.index=parse((ROOT/'vectors.json').read_bytes())
    def put(self,value):
        raw=json.dumps(value,ensure_ascii=False,separators=(',',':')).encode()
        digest=sha256(raw);(self.root/'objects'/digest).write_bytes(raw);return digest
    def record(self,name='source-free'):
        ref=copy.deepcopy(next(v['ref'] for v in self.index['vectors'] if v['name']==name))
        return ref,parse((self.root/'objects'/ref['digest']).read_bytes())
    def save(self,ref,record):
        ref['digest']=self.put(record);return ref
    def membership_child(self, parent_ref, parent, action='remove', ids=None, universe=None):
        from reader import program_digest
        universe_ref,universe_record=universe or (parent_ref,parent)
        before=parse((self.root/'objects'/parent['representation']['object']).read_bytes())
        all_program=parse((self.root/'objects'/universe_record['representation']['object']).read_bytes())
        current={s['id']['rawValue'] for s in before['strokes']}
        ids=ids if ids is not None else [before['strokes'][-1]['id']['rawValue']]
        selected=set(ids)
        target=current-selected if action=='remove' else current|selected if action=='restore' else selected
        program=copy.deepcopy(all_program)
        program['id']['rawValue']='00000000-0000-4000-8000-000000000099'
        program['strokes']=[s for s in program['strokes'] if s['id']['rawValue'] in target]
        digest=program_digest(program);program['contentHash']['bytes']=list(bytes.fromhex(digest))
        ref,record=self.record('pruned-child')
        record['parent']={'state':'present','ref':copy.deepcopy(parent_ref)}
        record['input']=copy.deepcopy(parent['input']);record['requiredFeatures']=parent['requiredFeatures'].copy()
        record['representation']=copy.deepcopy(parent['representation'])
        record['representation'].update(object=self.put(program),programHash=digest)
        claim={'profile':'adaptiveplotter.stroke-membership/1','action':action,
               'strokeIDs':[{'rawValue':v} for v in ids],'parent':copy.deepcopy(parent_ref),
               'universe':copy.deepcopy(universe_ref),'before':parent['representation']['programHash'],'after':digest}
        record['producer']={'id':'adaptiveplotter.stroke-membership','version':'1','record':self.put(claim)}
        return self.save(ref,record),record,claim,program
    def save_membership(self,ref,record,claim,program):
        from reader import program_digest
        digest=program_digest(program);program['contentHash']['bytes']=list(bytes.fromhex(digest))
        record['representation'].update(object=self.put(program),programHash=digest)
        claim['after']=digest;record['producer']['record']=self.put(claim)
        return self.save(ref,record)
    def test_membership_remove_restore_and_replace(self):
        parent_ref,parent=self.record('parent')
        ref,record,_,_=self.membership_child(parent_ref,parent)
        result=drawing(self.root,ref);self.assertTrue(result['producerVerified'])
        self.assertEqual(len(result['points']),2)
        p=parse((self.root/'objects'/parent['representation']['object']).read_bytes())
        restored,_,_,_=self.membership_child(ref,record,'restore',[p['strokes'][-1]['id']['rawValue']],(parent_ref,parent))
        self.assertEqual(len(drawing(self.root,restored)['points']),4)
        replaced,_,_,_=self.membership_child(ref,record,'membership',[p['strokes'][-1]['id']['rawValue']],(parent_ref,parent))
        self.assertEqual(len(drawing(self.root,replaced)['points']),2)
    def test_membership_historical_catalog_proof_survives_lineage(self):
        import struct,uuid
        from reader import program_digest
        pref,parent=self.record('source-free')
        program=parse((self.root/'objects'/parent['representation']['object']).read_bytes())
        style=program['strokes'][0]['style']
        source='adaptiveplotter.builtin.metricSquare40.v1'
        style_bytes=b'APCB\x00\x01'+struct.pack('>d',style['nominalLineWidth'])+uuid.UUID(style['penProfileID']['rawValue']).bytes
        seed='program:'+source+':'+sha256(style_bytes)
        def stable(value):
            raw=bytearray(bytes.fromhex(sha256(value.encode()))[:16]);raw[6]=(raw[6]&15)|80;raw[8]=(raw[8]&63)|128
            return {'rawValue':str(uuid.UUID(bytes=bytes(raw)))}
        paths=[[(0,0),(40,0),(40,40),(0,40),(0,0)],[(0,0),(40,40)],[(40,0),(0,40)]]
        program.update(id=stable(seed),fieldExtent={'width':40,'height':40},
                       source={'kind':'built-in-vector-catalog','sourceIdentifier':source})
        program['strokes']=[{'id':stable('stroke:'+seed+':'+str(i)),
                             'path':{'points':[{'x':x,'y':y} for x,y in points]},
                             'style':copy.deepcopy(style),'semanticRole':0,'ordering':i}
                            for i,points in enumerate(paths)]
        digest=program_digest(program);program['contentHash']['bytes']=list(bytes.fromhex(digest))
        receipt=parse((self.root/'objects'/parent['producer']['record']).read_bytes())
        receipt.update(entry='metricSquare40',sourceIdentifier=source,historicalUnits='millimeters')
        proof=self.put(receipt);parent['producer']['record']=proof
        parent['representation'].update(object=self.put(program),programHash=digest,
            historicalUnits={'state':'known','units':'millimeters','producerReceipt':proof})
        pref=self.save(pref,parent)
        self.assertTrue(drawing(self.root,pref)['producerVerified'])
        child,child_record,_,_=self.membership_child(pref,parent)
        self.assertTrue(drawing(self.root,child)['producerVerified'])
        descendant,descendant_record,claim,descendant_program=self.membership_child(
            child,child_record,universe=(pref,parent))
        self.assertTrue(drawing(self.root,descendant)['producerVerified'])
        restored,_,_,_=self.membership_child(descendant,descendant_record,'restore',
            [program['strokes'][-1]['id']['rawValue']],(pref,parent))
        self.assertTrue(drawing(self.root,restored)['producerVerified'])
        self.assertEqual(len(drawing(self.root,restored)['points']),7)
        descendant_record['representation']['historicalUnits']['producerReceipt']=self.put({'forged':'proof'})
        forged=self.save_membership(descendant,descendant_record,claim,descendant_program)
        with self.assertRaisesRegex(ValueError,'membership units'):drawing(self.root,forged)
        # A forged root receipt is also rejected through recursive parent admission.
        parent['representation']['historicalUnits']['producerReceipt']=self.put({'forged':'root'})
        bad_parent=self.save(pref,parent)
        bad_child,_,_,_=self.membership_child(bad_parent,parent)
        with self.assertRaisesRegex(ValueError,'historical unit receipt'):drawing(self.root,bad_child)
    def test_membership_retains_requirements_and_allows_additions(self):
        parent_ref,parent=self.record('parent');parent['requiredFeatures']=['example.parent']
        parent_ref=self.save(parent_ref,parent)
        ref,record,claim,program=self.membership_child(parent_ref,parent)
        record['requiredFeatures'].append('example.child');ref=self.save(ref,record)
        self.assertTrue(drawing(self.root,ref)['blocked'])
        supported={'example.parent','example.child'}
        self.assertTrue(drawing(self.root,ref,supported_features=supported)['capabilities']['edit'])
        # All objects are hash-coherent; stripping a supported parent's declaration is still invalid.
        record['requiredFeatures']=['example.child'];ref=self.save_membership(ref,record,claim,program)
        with self.assertRaisesRegex(ValueError,'membership required features'):
            drawing(self.root,ref,supported_features=supported)
        record['producer']['id']='example.foreign';ref=self.save(ref,record)
        self.assertTrue(drawing(self.root,ref,supported_features=supported)['capabilities']['edit'])
    def test_membership_receipt_rejections(self):
        changes={
            'profile':lambda c:c.update(profile='adaptiveplotter.stroke-membership/99'),
            'action':lambda c:c.update(action='guess'),
            'parent':lambda c:c['parent'].update(digest='0'*64),
            'universe':lambda c:c['universe'].update(digest='0'*64),
            'before':lambda c:c.update(before='0'*64),
            'after':lambda c:c.update(after='0'*64),
            'duplicate':lambda c:c['strokeIDs'].append(copy.deepcopy(c['strokeIDs'][0])),
            'unknown':lambda c:c['strokeIDs'][0].update(rawValue='00000000-0000-4000-8000-000000000098'),
            'empty':lambda c:c.update(strokeIDs=[]),
            'restore-current':lambda c:c.update(action='restore'),
        }
        for name,change in changes.items():
            with self.subTest(name=name):
                pref,parent=self.record('parent');ref,record,claim,_=self.membership_child(pref,parent)
                change(claim);record['producer']['record']=self.put(claim)
                with self.assertRaises(ValueError):drawing(self.root,self.save(ref,record))
        pref,parent=self.record('parent');ref,record,claim,_=self.membership_child(pref,parent)
        p=parse((self.root/'objects'/parent['representation']['object']).read_bytes())
        for action,ids in [('remove',[s['id'] for s in p['strokes']]),('membership',[]),('membership',[s['id'] for s in p['strokes']])]:
            claim.update(action=action,strokeIDs=ids);record['producer']['record']=self.put(claim)
            with self.subTest(action=action,ids=ids),self.assertRaises(ValueError):drawing(self.root,self.save(ref,record))
        record['producer']['version']='99';ref=self.save(ref,record)
        self.assertFalse(drawing(self.root,ref)['producerVerified'])
    def test_membership_coherently_changed_geometry_and_units(self):
        mutations={
            'point':lambda r,p:p['strokes'][0]['path']['points'][0].update(x=6),
            'style':lambda r,p:p['strokes'][0]['style'].update(nominalLineWidth=0.7),
            'order':lambda r,p:p['strokes'][0].update(ordering=42),
            'field':lambda r,p:p['fieldExtent'].update(width=101),
            'source':lambda r,p:p['source'].update(sourceIdentifier='changed'),
            'width':lambda r,p:r['representation'].update(nominalPenWidthMillimeters=0.7),
            'physical-field':lambda r,p:r['representation'].update(intendedPhysicalFieldMillimeters={'width':100,'height':100}),
            'input':lambda r,p:r.update(input={'state':'unavailable','reason':'changed'}),
        }
        for name,change in mutations.items():
            with self.subTest(name=name):
                pref,parent=self.record('parent');ref,record,claim,program=self.membership_child(pref,parent)
                change(record,program)
                with self.assertRaises(ValueError):drawing(self.root,self.save_membership(ref,record,claim,program))
    def test_membership_decoded_stroke_equality(self):
        from reader import program_digest
        pref,parent=self.record('parent')
        original=parse((self.root/'objects'/parent['representation']['object']).read_bytes())
        original['strokes'][0]['path']['points'][0]['x']=0
        original['source']['sourceIdentifier']='cafe\u0301'
        digest=program_digest(original);original['contentHash']['bytes']=list(bytes.fromhex(digest))
        parent['representation'].update(object=self.put(original),programHash=digest)
        pref=self.save(pref,parent);ref,record,claim,program=self.membership_child(pref,parent)
        program['source']['sourceIdentifier']='caf\u00e9'
        program['strokes'][0]['path']['points'][0]['x']=-0.0
        for s in program['strokes']:
            s['id']['rawValue']=s['id']['rawValue'].upper()
            s['style']['penProfileID']['rawValue']=s['style']['penProfileID']['rawValue'].upper()
            s['unknownOptional']={'preserved':True};s['path']['unknownOptional']='ignored'
        self.assertTrue(drawing(self.root,self.save_membership(ref,record,claim,program))['producerVerified'])
    def test_coherent_invalid_programs(self):
        from reader import program_digest
        mutations=[
            lambda p:p['strokes'][0]['path'].update(points=[{'x':5,'y':50}]),
            lambda p:p['strokes'][0]['path'].update(points=[{'x':5,'y':50}]*2),
            lambda p:p['fieldExtent'].update(width=0),
            lambda p:p['strokes'][0]['style'].update(nominalLineWidth=0),
            lambda p:p['strokes'][0].update(semanticRole=2),
            lambda p:p['strokes'][0]['path']['points'][0].update(x=-1),
            lambda p:p['source'].update(kind=''),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                ref,r=self.record();p=parse((self.root/'objects'/r['representation']['object']).read_bytes())
                mutate(p);digest=program_digest(p);p['contentHash']['bytes']=list(bytes.fromhex(digest))
                r['representation'].update(object=self.put(p),programHash=digest)
                # Unknown producer isolates native validity from catalog validation.
                r['producer']['id']='example.external'
                with self.assertRaises(ValueError):drawing(self.root,self.save(ref,r))
    def test_native_scalar_rejections(self):
        from reader import validate_program
        _,r=self.record();original=parse((self.root/'objects'/r['representation']['object']).read_bytes())
        for change in [lambda p:p.update(schemaVersion=True),lambda p:p['strokes'][0].update(ordering=True),lambda p:p['strokes'][0]['style'].update(nominalLineWidth=True),lambda p:p['strokes'][0]['id'].update(rawValue='not-a-uuid'),lambda p:p['contentHash'].update(bytes=[True]*32)]:
            p=copy.deepcopy(original);change(p)
            with self.assertRaises(ValueError):validate_program(p)
        p=copy.deepcopy(original);p['strokes']*=2
        with self.assertRaises(ValueError):validate_program(p)
    def test_catalog_recipe_negative(self):
        for change in [lambda x:x['tessellation'].update(maximumChordError=-1),lambda x:x['tessellation'].update(algorithmRevision=2),lambda x:x.update(entry='square'),lambda x:x.update(sourceIdentifier='pretend')]:
            ref,r=self.record();receipt=parse((self.root/'objects'/r['producer']['record']).read_bytes());receipt.setdefault('tessellation',{'maximumChordError':0.25,'algorithmRevision':1,'maximumSegments':4096});change(receipt)
            r['producer']['record']=self.put(receipt)
            with self.assertRaises(ValueError):drawing(self.root,self.save(ref,r))
    def test_source_declaration_contradiction(self):
        ref,r=self.record();r['producer']['id']='example.external';r['input']['ref']=ref.copy()
        with self.assertRaises(ValueError):drawing(self.root,self.save(ref,r))
    def test_unsafe_object_and_depth(self):
        from reader import object_bytes
        for value in ('../vectors.json','A'*64,'a'*63):
            with self.assertRaises(ValueError):object_bytes(self.root,value)
        with self.assertRaises(ValueError):parse(b'['*66+b'0'+b']'*66)
        with self.assertRaises(ValueError):parse(b'{"x":"\\ud800"}')
    def test_timestamps(self):
        from reader import timestamp
        timestamp({'wallTime':'2026-11-06T12:00:00.123456-07:00','event':{'clockID':'c','bootSession':'550e8400-e29b-41d4-a716-446655440000','ticks':'1'*100,'ticksPerSecond':1}})
        for value in ({},{'wallTime':'bad'},{'event':{'clockID':'c','bootSession':'550e8400-e29b-41d4-a716-446655440000','ticks':'01','ticksPerSecond':1}},{'wallTime':'2026-11-06T12:00:00Z','event':{'clockID':'c','bootSession':'BAD','ticks':'1','ticksPerSecond':1}}):
            with self.assertRaises(ValueError):timestamp(value)
    def test_normative_asset_descriptor_context(self):
        from reader import asset
        descriptor=copy.deepcopy(self.index['assets'][0]);inline=copy.deepcopy(descriptor)
        del inline['pixelLayout']
        self.assertTrue(asset(self.root,inline,{descriptor['object']:descriptor}))
        with self.assertRaises(ValueError):asset(self.root,inline)
        for key,value in [('rowStride',1),('height',3),('bitDepth',16)]:
            d=copy.deepcopy(descriptor);d['pixelLayout'][key]=value
            with self.assertRaises(ValueError):asset(self.root,d)
        d=copy.deepcopy(descriptor);d['pixelLayout']['orientation']='unfamiliar'
        self.assertFalse(asset(self.root,d))
        d=copy.deepcopy(descriptor);d['byteLength']+=1
        with self.assertRaises(ValueError):asset(self.root,d,{descriptor['object']:descriptor})
    def test_feature_propagation(self):
        ref,r=self.record('photo');inp_ref=r['input']['ref'];inp=parse((self.root/'objects'/inp_ref['digest']).read_bytes());photo_ref=inp['photo'];photo=parse((self.root/'objects'/photo_ref['digest']).read_bytes())
        photo['requiredFeatures']=['example.future'];photo_ref['digest']=self.put(photo);inp_ref['digest']=self.put(inp)
        ref=self.save(ref,r)
        result=drawing(self.root,ref)
        self.assertFalse(result['blocked']);self.assertFalse(result['sourceSupported'])
        self.assertTrue(result['capabilities']['preview']);self.assertTrue(result['capabilities']['plot']);self.assertTrue(result['capabilities']['edit'])
        self.assertFalse(result['capabilities']['regenerate']);self.assertFalse(result['capabilities']['train'])
        self.assertTrue(drawing(self.root,ref,supported_features={'example.future'})['sourceSupported'])
    def test_normative_schema_vectors(self):
        from jsonschema import Draft202012Validator,FormatChecker
        schema=parse((ROOT.parents[3]/'Resources/DrawingExchange/v1/schema.json').read_bytes())
        Draft202012Validator.check_schema(schema)
        count=0
        for path in (ROOT/'objects').iterdir():
            try:value=parse(path.read_bytes())
            except (ValueError,UnicodeError):continue
            if isinstance(value,dict) and value.get('profile') in ('adaptiveplotter.photo/1','adaptiveplotter.image-input/1','adaptiveplotter.drawing/1'):
                Draft202012Validator(schema,format_checker=FormatChecker()).validate(value);count+=1
        for value in self.index['assets']:
            selected={**schema,'oneOf':[{'$ref':'#/$defs/AssetDescriptor'}]}
            Draft202012Validator(selected,format_checker=FormatChecker()).validate(value);count+=1
        self.assertGreaterEqual(count,20)

    def test_descriptor_only_in_index_closure(self):
        ref,r=self.record('masked-rotated');iref=r['input']['ref'];inp=parse((self.root/'objects'/iref['digest']).read_bytes())
        pref=inp['photo'];photo=parse((self.root/'objects'/pref['digest']).read_bytes())
        descriptors={}
        for owner,key in ((photo,'original'),(inp,'raster'),(inp['mask'],'asset')):
            descriptor=owner[key];descriptors[descriptor['object']]=copy.deepcopy(descriptor);del descriptor['pixelLayout']
        pref['digest']=self.put(photo);iref['digest']=self.put(inp);ref=self.save(ref,r)
        self.assertFalse(drawing(self.root,ref,asset_descriptors=descriptors)['blocked'])
        with self.assertRaises(ValueError):drawing(self.root,ref)
    def test_coherent_bad_image_record(self):
        for mutation in ('dimension','mask','timestamp','basis'):
            ref,r=self.record('masked-rotated');iref=r['input']['ref'];inp=parse((self.root/'objects'/iref['digest']).read_bytes())
            if mutation=='dimension':inp['raster']['pixelLayout']['width']=3
            elif mutation=='mask':inp['mask']={'state':'none'}
            elif mutation=='basis':inp['pixelBasis']['dimensions']['height']=3
            else:
                pref=inp['photo'];photo=parse((self.root/'objects'/pref['digest']).read_bytes());photo['imported']['time']['event']={'clockID':'c','bootSession':'550e8400-e29b-41d4-a716-446655440000','ticks':'1','ticksPerSecond':True};pref['digest']=self.put(photo)
            iref['digest']=self.put(inp)
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):drawing(self.root,self.save(ref,r))
    def test_unknown_producer_version_and_opaque_representation(self):
        ref,r=self.record();r['producer']['version']='999'
        self.assertFalse(drawing(self.root,self.save(ref,r))['producerVerified'])
        r['representation']['kind']='example.future/2';ref=self.save(ref,r)
        self.assertTrue(drawing(self.root,ref)['opaque'])
        (self.root/'objects'/r['representation']['object']).write_bytes(b'corrupted')
        with self.assertRaises(ValueError):drawing(self.root,ref)
    def test_array_layout(self):
        from reader import asset
        descriptor=copy.deepcopy(next(a for a in self.index['assets'] if 'arrayLayout' in a))
        self.assertTrue(asset(self.root,descriptor))
        descriptor['arrayLayout']['shape']=[3,2]
        with self.assertRaises(ValueError):asset(self.root,descriptor)

    def test_unknown_input_schema_preserves_geometry(self):
        ref,r=self.record('photo');iref=r['input']['ref']
        unknown={'profile':'adaptiveplotter.image-input/99','ref':{k:iref[k] for k in ('issuer','revision')},'unknownOptional':{'preserve':'verbatim'}}
        iref['digest']=self.put(unknown);unknown_bytes=(self.root/'objects'/iref['digest']).read_bytes()
        result=drawing(self.root,self.save(ref,r))
        self.assertFalse(result['blocked']);self.assertFalse(result['sourceSupported'])
        self.assertTrue(result['capabilities']['preview']);self.assertTrue(result['capabilities']['plot']);self.assertTrue(result['capabilities']['edit'])
        self.assertFalse(result['capabilities']['regenerate']);self.assertFalse(result['capabilities']['train'])
        self.assertEqual(result['dependencies'][0]['bytes'],unknown_bytes)
        self.assertTrue(result['dependencyReasons'])
        (self.root/'objects'/iref['digest']).write_bytes(b'corrupt')
        with self.assertRaises(ValueError):drawing(self.root,self.save(ref,r))
    def test_unknown_photo_schema_and_encoded_source(self):
        for kind in ('photo-major','encoded','orientation'):
            with self.subTest(kind=kind):
                ref,r=self.record('photo');iref=r['input']['ref'];inp=parse((self.root/'objects'/iref['digest']).read_bytes());pref=inp['photo'];photo=parse((self.root/'objects'/pref['digest']).read_bytes())
                if kind=='photo-major':photo={'profile':'adaptiveplotter.photo/99','ref':photo['ref'],'opaqueFacts':[1,2]}
                elif kind=='encoded':
                    photo['original']['encoding']='png';photo['original']['mediaType']='image/png';del photo['original']['pixelLayout']
                else:photo['original']['pixelLayout']['orientation']='future-orientation'
                pref['digest']=self.put(photo);iref['digest']=self.put(inp)
                result=drawing(self.root,self.save(ref,r))
                self.assertFalse(result['blocked']);self.assertFalse(result['sourceSupported'])
                self.assertTrue(result['capabilities']['preview']);self.assertTrue(result['capabilities']['plot']);self.assertTrue(result['capabilities']['edit'])
    def test_drawing_feature_blocks_geometry(self):
        ref,r=self.record('unknown-required-feature');result=drawing(self.root,ref)
        self.assertTrue(result['blocked'])
        for operation in ('preview','plot','edit','regenerate','train'):self.assertFalse(result['capabilities'][operation])
    def test_unknown_parent_schema_preserves_child_geometry(self):
        ref,r=self.record('pruned-child');pref=r['parent']['ref']
        pref['digest']=self.put({'profile':'adaptiveplotter.drawing/99','ref':{k:pref[k] for k in ('issuer','revision')}})
        result=drawing(self.root,self.save(ref,r))
        self.assertFalse(result['blocked']);self.assertFalse(result['sourceSupported']);self.assertTrue(result['capabilities']['edit'])

    def test_raw_rgba_bgra_encoding_layout_contract(self):
        from reader import asset
        raw=bytes([1,2,3,4]);digest=sha256(raw);(self.root/'objects'/digest).write_bytes(raw)
        for encoding,fmt,order in (
            ('raw-rgba8','rgba',['red','green','blue','alpha']),
            ('raw-bgra8','bgra',['blue','green','red','alpha']),
        ):
            descriptor={'object':digest,'byteLength':4,'mediaType':'application/octet-stream','encoding':encoding,
                'pixelLayout':{'width':1,'height':1,'pixelFormat':fmt,'componentType':'uint8','bitDepth':8,
                    'channelOrder':order,'rowStride':4,'byteOrder':'not-applicable','orientation':'up','colorInterpretation':'sRGB'}}
            self.assertTrue(asset(self.root,descriptor))
            for mutation in ('opposite-encoding','opposite-layout','wrong-component'):
                with self.subTest(encoding=encoding,mutation=mutation):
                    bad=copy.deepcopy(descriptor)
                    if mutation=='opposite-encoding':bad['encoding']='raw-bgra8' if encoding=='raw-rgba8' else 'raw-rgba8'
                    elif mutation=='opposite-layout':
                        bad['pixelLayout']['pixelFormat']='bgra' if fmt=='rgba' else 'rgba'
                        bad['pixelLayout']['channelOrder']=list(reversed(order[:3]))+['alpha']
                    else:bad['pixelLayout']['componentType']='int8'
                    with self.assertRaises(ValueError):asset(self.root,bad)

    def test_catalog_intended_physical_field_claim(self):
        ref,r=self.record();r['representation']['intendedPhysicalFieldMillimeters']={'width':100,'height':100}
        with self.assertRaises(ValueError):drawing(self.root,self.save(ref,r))
        receipt=parse((self.root/'objects'/r['producer']['record']).read_bytes())
        receipt['intendedPhysicalFieldMillimeters']={'width':100,'height':100};r['producer']['record']=self.put(receipt)
        self.assertTrue(drawing(self.root,self.save(ref,r))['producerVerified'])
        for bad in ({'width':True,'height':100},{'width':100,'height':0},{'width':50,'height':100}):
            r['representation']['intendedPhysicalFieldMillimeters']=bad
            with self.assertRaises(ValueError):drawing(self.root,self.save(ref,r))
    def test_catalog_historical_units_proof(self):
        ref,r=self.record();r['representation']['historicalUnits']={'state':'known','units':'millimeters','producerReceipt':r['producer']['record']}
        with self.assertRaises(ValueError):drawing(self.root,self.save(ref,r))
        receipt=parse((self.root/'objects'/r['producer']['record']).read_bytes());receipt['historicalUnits']='millimeters';r['producer']['record']=self.put(receipt)
        r['representation']['historicalUnits']['producerReceipt']=r['producer']['record']
        self.assertTrue(drawing(self.root,self.save(ref,r))['producerVerified'])
        r['representation']['historicalUnits']['producerReceipt']='0'*64
        with self.assertRaises(ValueError):drawing(self.root,self.save(ref,r))
        r['representation']['historicalUnits']={'state':'unknown','units':'millimeters'}
        with self.assertRaises(ValueError):drawing(self.root,self.save(ref,r))

if __name__=="__main__": unittest.main()
