"""Binding-inspection fixtures are disposable, never rewritten golden vectors.

The synthetic native dictionaries test binding rejection only, not Swift owner
admission or physical-plan mathematics. A separate opt-in test consumes actual
Swift-exported result/task carriers for cross-language interoperability.
"""
import copy
import json
import os
from pathlib import Path
import shutil
import unittest
import uuid
import test_carrier as fixture
from carrier import import_carrier, inspect_result, task_index, task_grouping_keys, TASK_CONTRACTS, Limits
from reader import parse, sha256
import native


class NativeInspectionTests(unittest.TestCase):
    def setUp(self):
        self.f=fixture.CarrierTests(methodName='runTest');self.f.setUp()
        self.addCleanup(self.f.doCleanups)

    def remove_superseded_wrapper(self,index,wrapper,original_source):
        """Remove only the replaced wrapper, never an asset of the source scope."""
        if wrapper['object'] in {asset['object'] for asset in original_source['assets']}:return
        index['assets']=[asset for asset in index['assets'] if asset['object']!=wrapper['object']]
        path=self.f.bag/'data/objects/sha256'/wrapper['object']
        if path.exists():path.unlink()

    def make(self, fault=None, terminal=True, encoding=native.PROPOSAL, stroke_count=1, environment='simulation'):
        uid,run=self.f.result_bag()
        index=self.f.index();drawing=index['roots'][0]
        source=parse((self.f.bag/f"data/drawings/{drawing['issuer']}/{drawing['revision']}/drawing.json").read_bytes())
        program=parse((self.f.bag/'data/objects/sha256'/source['representation']['object']).read_bytes())
        def asset(value,encoding):
            raw=json.dumps(value,separators=(',',':')).encode();h=sha256(raw)
            (self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
            descriptor={'object':h,'byteLength':len(raw),'mediaType':'application/json','encoding':encoding}
            index['assets'].append(descriptor);return descriptor
        h='b'*64;raw_hash={'bytes':list(bytes.fromhex(h))};plan_id={'rawValue':raw_hash}
        plan={'schemaVersion':1,'revisionID':plan_id,'contentHash':raw_hash,
              'sourceProgramID':program['id'],'sourceProgramContentHash':program['contentHash'],
              'strokes':[{'fixture':'binding-only-no-physical-plan-validation',
                          'logicalStrokeID':{'rawValue':str(uuid.UUID(int=100+i))},
                          'endingCheckpointID':{'rawValue':str(uuid.UUID(int=200+i))}} for i in range(stroke_count)]}
        plan_asset=asset(plan,'adaptiveplotter.local-prepared-plan/1')
        options=asset(dict(readiness='fixture',**({'environment':environment} if environment is not None else {})),'adaptiveplotter.local-medium-options/1')
        old_job=index['jobs'][0]
        receipt=parse((self.f.bag/f'data/jobs/{uid}/{uid}/receipt.json').read_bytes())
        receipt.update(preparedPlan=plan_asset,requestedMediumOptions=options)
        raw=json.dumps(receipt,separators=(',',':')).encode()
        (self.f.bag/f'data/jobs/{uid}/{uid}/receipt.json').write_bytes(raw)
        job={'engine':uid,'job':uid,'receiptDigest':sha256(raw)}
        binding={'drawing':drawing,'job':receipt['handle'],'key':{'namespace':uid,'request':uid},
                 'requestDigest':receipt['client']['requestDigest'],'issuance':receipt['issuance'],
                 'preparedPlan':plan_asset,'physicalPlanID':plan_id,'physicalPlanHash':h,'options':options}
        body={'requestID':uid,'plan':plan,'placementID':uid,'role':'fixture-role',
              'recordedAt':{'monotonicNanoseconds':123,'wallTime':0},
              'context':{'program':program,'paper':{},'candidate':{'authoredDrawing':drawing,'candidateID':drawing['digest'],
                  'contentHash':{'bytes':list(bytes.fromhex(drawing['digest']))},'sourceProgram':program,'programContentHash':program['contentHash']}}}
        state={'intent':dict(body,runID={'rawValue':run},issuance=binding),'baselines':[],
               'progressFrames':[],'inkDispatchPossible':True}
        record={'schemaVersion':4,'runID':{'rawValue':run},'requestID':uid,'role':body['role'],
                'paper':{},'plan':{'revisionID':plan_id,'contentHash':raw_hash,'executionPlan':plan},
                'executionFrontiers':{'plannedStrokeCount':stroke_count,'commandedStrokeCount':stroke_count,'controllerCompletedStrokeCount':stroke_count,'inkVerifiedStrokeCount':0},
                'executionDisposition':{'cancelled':{'reason':'fixture'}},'observation':{'notAttempted':{'_0':'executionCancelledBeforeObservation'}},
                'attemptEvidence':{'intent':copy.deepcopy(state['intent']),'baselines':[],'progressFrames':[],'terminalFrames':[]}}
        snapshot={'profile':'adaptiveplotter.plot-attempt/1','requiredFeatures':[],'issuerArchive':uid,'run':run,'sequence':1,'previous':None,
                  'sealed':terminal,'drawing':drawing,'job':job,'environment':'simulation','state':'cancelled' if terminal else 'interrupted',
                  'dispatch':'possibleInk','observation':'unavailable','assessments':[],'plan':plan_asset}
        if fault:fault(body,binding,state,record,snapshot)
        proposal=asset({'body':body,'binding':binding},encoding)
        raw_state=asset(state,native.ATTEMPT)
        entries=[{'kind':'example.raw-attempt/1','status':'present','asset':raw_state}]
        raw_terminal=asset(record,native.TERMINAL) if terminal else None
        if raw_terminal:entries.append({'kind':'example.raw-terminal/1','status':'present','asset':raw_terminal})
        entries.extend(native.observation_entries(record if terminal else None,raw_terminal))
        unavailable={'kind':'example.frontier/1','status':'unavailable','reason':'No physical interpretation in this fixture.'}
        coverage={'profile':'adaptiveplotter.coverage/1','requiredFeatures':[],
                  'includedAsOf':{'wallTime':index['includedAsOf']},'rawAttempt':raw_state,'entries':entries,
                  'frontiers':{k:unavailable for k in ('planned','commanded','controllerCompleted','inkVerified')}}
        if raw_terminal:coverage['rawTerminal']=raw_terminal
        basis={'proposal':proposal['object'],'attempt':raw_state['object']}
        if raw_terminal:basis['terminal']=raw_terminal['object']
        coverage['rawContent']=sha256(json.dumps(basis,sort_keys=True,separators=(',',':')).encode())
        counts={'planned':stroke_count,'commanded':stroke_count,'controllerCompleted':stroke_count,'inkVerified':0} if terminal else {'planned':stroke_count}
        if not terminal and state['progressFrames']:
            p=state['progressFrames'][-1]['progress'];counts.update(commanded=p['commandedStrokeCount'],controllerCompleted=p['controllerCompletedStrokeCount'])
        for name,count in counts.items():
            coverage['frontiers'][name]={'kind':'adaptiveplotter.frontier/'+name,'status':'present','count':count,'asset':raw_terminal or raw_state}
        coverage_asset=asset(coverage,native.COVERAGE)
        snapshot.update(intent=proposal['object'],coverage=coverage_asset['object'],terminalRecord=raw_terminal['object'] if raw_terminal else None)
        for path in (self.f.bag/'data/attempts').rglob('attempt.json'):path.unlink()
        raw=json.dumps(snapshot,separators=(',',':')).encode()
        path=self.f.bag/f'data/attempts/{uid}/{run}/1/attempt.json';path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
        ref={'archive':uid,'run':run,'sequence':1,'digest':sha256(raw)}
        index.update(jobs=[job],attempts=[ref]);self.f.put_index(index)
        return self.f.bag

    def progress(self, body, count):
        plan=body['plan']
        return {'media':{},'progress':{'operationID':{'rawValue':body['requestID']},'planRevisionID':plan['revisionID'],
            'plannedStrokeCount':len(plan['strokes']),'commandedStrokeCount':count,'controllerCompletedStrokeCount':count,
            'completedStrokeIDs':[s['logicalStrokeID'] for s in plan['strokes'][:count]],
            'completedCheckpointIDs':[s['endingCheckpointID'] for s in plan['strokes'][:count]],
            'plannedSegmentCount':len(plan['strokes']),'submittedSegmentCount':count,'controllerCompletedSegmentCount':count}}

    def interruption_task_bag(self, eligible=True):
        index=self.f.index();admitted=import_carrier(self.f.bag,self.f.stage);original=copy.deepcopy(index)
        ref=index['attempts'][0];snapshot=parse((self.f.bag/f"data/attempts/{ref['archive']}/{ref['run']}/{ref['sequence']}/attempt.json").read_bytes())
        def asset(value,encoding):
            raw=json.dumps(value,separators=(',',':')).encode();h=sha256(raw);(self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
            return {'object':h,'byteLength':len(raw),'mediaType':'application/json','encoding':encoding}
        source=asset(original,'adaptiveplotter.exchange/1');contract=TASK_CONTRACTS['adaptiveplotter.interruption-state/1']
        task={'profile':'adaptiveplotter.drawing-evidence-task/1','requiredFeatures':[],'id':str(uuid.uuid4()),
            'task':'adaptiveplotter.interruption-state/1','taskVersion':'1','inputContract':contract[0],'labelContract':contract[1],
            'sourceIndex':source,'includedAsOf':index['includedAsOf'],'extractorRevision':'fixture/1',
            'modelRevisionUnavailableReason':'No model revision was recorded for this frozen evidence task.',
            'entries':[{'selection':{'job':index['jobs'][0],'snapshot':ref,'assessments':[],'group':'source','split':'training','relatedGroups':[]},
                'drawing':snapshot['drawing'],'outcome':snapshot['state'],'environment':snapshot['environment'],'claims':[],
                'groupingKeys':sorted(task_grouping_keys(admitted,snapshot['drawing'])),'eligible':eligible,'exclusions':[] if eligible else ['Selected predecessor proof is unavailable.'],'limitations':[]}]}
        scope=asset(task,'adaptiveplotter.drawing-evidence-task/1');self.f.put_index(task_index(original,source,scope))

    def task_bag(self, assessment_mode=None):
        self.f.result_bag(refused=True);index=self.f.index();drawing=index['roots'][0]
        index['example.vendor-index']={'preserved':True}
        index['assets'][0]['example.vendor-descriptor']={'preserved':True}
        def asset(value,encoding):
            raw=json.dumps(value,separators=(',',':')).encode();h=sha256(raw)
            (self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
            d={'object':h,'byteLength':len(raw),'mediaType':'application/json','encoding':encoding};index['assets'].append(d);return d
        assessments=[];claims=[]
        if assessment_mode:
            issuer='33333333-3333-4333-8333-333333333333';revision='44444444-4444-4444-8444-444444444444'
            record={'profile':'adaptiveplotter.assessment/1','requiredFeatures':[],'ref':{'issuer':issuer,'revision':revision},
                'targets':[{'kind':'drawing','ref':drawing}],'reviewer':{'kind':'human','id':'fixture.operator'},
                'time':{'wallTime':index['includedAsOf']},'question':{'id':'fixture.observation','version':'1','text':'Recorded claim'},
                'answer':{'type':'fixture.observation','value':True},'supportingAssets':[]}
            if assessment_mode in ('pruning','choice','admin'):
                record['answer']={'type':{'pruning':'adaptiveplotter.flow-pruning','choice':'adaptiveplotter.flow-choice','admin':'adaptiveplotter.recorded-ranking-revision'}[assessment_mode],'value':False}
                if assessment_mode=='admin':record['reviewer']={'kind':'algorithm','id':'adaptiveplotter.flow-feedback-adapter','version':'1'}
            raw=json.dumps(record,separators=(',',':')).encode();ref={'issuer':issuer,'revision':revision,'digest':sha256(raw)}
            if assessment_mode=='unindexed':asset(record,'example.unindexed-claim/1')
            else:
                path=self.f.bag/f'data/assessments/{issuer}/{revision}.json';path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
                index['assessments']=[ref]
            selected=dict(ref)
            if assessment_mode=='spoof':selected['issuer']='55555555-5555-4555-8555-555555555555'
            assessments=[selected]*(2 if assessment_mode=='duplicate' else 1)
            claims=[dict(reference=r,kind='uninterpreted-claim',answerType=record['answer']['type'],reviewerKind=record['reviewer']['kind'],reviewerID=record['reviewer']['id'],**({'reviewerVersion':record['reviewer']['version']} if 'version' in record['reviewer'] else {})) for r in assessments]
        self.f.put_index(index)
        admitted=import_carrier(self.f.bag,self.f.stage)
        keys=sorted(task_grouping_keys(admitted,drawing))
        original=copy.deepcopy(index)
        source=asset(original,'adaptiveplotter.exchange/1')
        contract=TASK_CONTRACTS['adaptiveplotter.result-inspection/1']
        task={'profile':'adaptiveplotter.drawing-evidence-task/1','requiredFeatures':[],'id':'66666666-6666-4666-8666-666666666666',
            'task':'adaptiveplotter.result-inspection/1','taskVersion':'1','inputContract':contract[0],'labelContract':contract[1],
            'sourceIndex':source,'includedAsOf':index['includedAsOf'],'extractorRevision':'fixture/1',
            'modelRevisionUnavailableReason':'No model revision was recorded for this frozen evidence task.',
            'entries':[{'selection':{'job':index['jobs'][0],'assessments':assessments,'group':'source','split':'inspection','relatedGroups':[]},
                'drawing':drawing,'outcome':'refused','claims':claims,'groupingKeys':keys,'eligible':True,'exclusions':[],'limitations':[]}]}
        scope=asset(task,'adaptiveplotter.drawing-evidence-task/1')
        self.f.put_index(task_index(original,source,scope))
        return task

    def native_chain(self, change=None, progress=False):
        self.make(terminal=False,stroke_count=8)
        index=self.f.index();ref=index['attempts'][0]
        path=self.f.bag/f"data/attempts/{ref['archive']}/{ref['run']}/1/attempt.json"
        template=parse(path.read_bytes())
        original_coverage=parse((self.f.bag/'data/objects/sha256'/template['coverage']).read_bytes())
        original_state=parse((self.f.bag/'data/objects/sha256'/original_coverage['rawAttempt']['object']).read_bytes())
        proposal=parse((self.f.bag/'data/objects/sha256'/template['intent']).read_bytes())
        def asset(value,encoding):
            raw=json.dumps(value,separators=(',',':')).encode();h=sha256(raw)
            (self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
            d={'object':h,'byteLength':len(raw),'mediaType':'application/json','encoding':encoding};index['assets'].append(d);return d
        pixels=b'1234';h=sha256(pixels);(self.f.bag/'data/objects/sha256'/h).write_bytes(pixels)
        pixel_asset={'object':h,'byteLength':len(pixels),'mediaType':'application/octet-stream','encoding':'raw-gray8'}
        index['assets'].append(dict(pixel_asset,dimensions={'width':2,'height':2},pixelLayout={
            'width':2,'height':2,'pixelFormat':'gray','componentType':'uint8','bitDepth':8,'channelOrder':['gray'],
            'rowStride':2,'byteOrder':'not-applicable','orientation':'up','colorInterpretation':'linear-gray'}))
        def media(name,ticks):
            return {'byteCount':4,'frame':{'frameID':name,'frameSHA256':h,'captureNanoseconds':ticks,
                'width':2,'height':2,'rowBytes':2,'pixelFormat':'gray8'}}
        baseline=media('baseline-a',200)
        states=[]
        for sequence in (1,2):
            state=copy.deepcopy(original_state);state['baselines']=[copy.deepcopy(baseline)]
            if progress:
                frame=self.progress(proposal['body'],2);frame['media']=media('progress-a',300);state['progressFrames']=[frame]
            states.append(state)
        if change:change(states)
        previous=None
        for sequence,state in enumerate(states,1):
            raw_state=asset(state,native.ATTEMPT);coverage=copy.deepcopy(original_coverage)
            coverage['rawAttempt']=raw_state;basis={'proposal':template['intent'],'attempt':raw_state['object']}
            coverage['rawContent']=sha256(json.dumps(basis,sort_keys=True,separators=(',',':')).encode())
            coverage['entries']=[]
            originals=[('adaptiveplotter.raw-baseline',r) for r in state['baselines']]+[('adaptiveplotter.raw-progress',r['media']) for r in state['progressFrames']]
            for kind,reference in originals:
                coverage['entries'].append({'kind':kind,'status':'present','asset':pixel_asset,
                    'rawFrameID':reference['frame']['frameID'],'rawCaptureTicks':str(reference['frame']['captureNanoseconds']),'captureClock':'unavailable'})
            coverage['entries'].extend(native.observation_entries(None,None))
            counts={'planned':8}
            if not state['inkDispatchPossible']:counts.update(commanded=0,controllerCompleted=0)
            if state['progressFrames']:
                p=state['progressFrames'][-1]['progress'];counts.update(commanded=p['commandedStrokeCount'],controllerCompleted=p['controllerCompletedStrokeCount'])
            for name in ('planned','commanded','controllerCompleted','inkVerified'):
                coverage['frontiers'][name]={'kind':'adaptiveplotter.frontier/'+name,'status':'present','count':counts[name],'asset':raw_state} if name in counts else {'kind':'adaptiveplotter.frontier/'+name,'status':'unavailable','reason':'No retained exact frontier.'}
            coverage_asset=asset(coverage,native.COVERAGE)
            snapshot=dict(template,sequence=sequence,previous=previous,coverage=coverage_asset['object'],state='interrupted' if state['inkDispatchPossible'] else 'staged')
            raw=json.dumps(snapshot,separators=(',',':')).encode();previous=sha256(raw)
            target=self.f.bag/f"data/attempts/{ref['archive']}/{ref['run']}/{sequence}/attempt.json";target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
        index['attempts']=[dict(ref,sequence=2,digest=previous)];self.f.put_index(index)
        return h

    def test_known_binding_is_inspectable_without_claiming_physical_plan_math(self):
        result=import_carrier(self.make(),self.f.stage)
        facts=inspect_result(result)
        self.assertEqual(len(facts['nativeBindings']),1)
        binding=facts['nativeBindings'][0]
        self.assertTrue(binding['nativeBindingVerified'])
        self.assertFalse(binding['physicalPlanCanonicalHashVerified'])
        self.assertEqual(binding['frontiers'],{'planned':1,'commanded':1,'controllerCompleted':1,'inkVerified':0})
        self.assertIn(native.PHYSICAL_LIMIT,result.unsupported)
        self.assertFalse(facts['retryAuthority']);self.assertFalse(facts['physicalValidityClaim'])

    def test_terminal_positive_frontier_cannot_be_cleaned_by_raw_false_and_envelope(self):
        def change(body,binding,state,record,snapshot):
            state['inkDispatchPossible']=False;snapshot['dispatch']='not-dispatched'
        with self.assertRaises(ValueError):import_carrier(self.make(change),self.f.stage)

    def test_terminal_raw_false_is_invalid_even_when_envelope_says_possible_ink(self):
        def change(body,binding,state,record,snapshot):state['inkDispatchPossible']=False
        with self.assertRaises(ValueError):import_carrier(self.make(change),self.f.stage)

    def test_terminal_intent_cannot_differ_from_original_raw_stage(self):
        def change(body,binding,state,record,snapshot):record['attemptEvidence']['intent']['requestID']='33333333-3333-4333-8333-333333333333'
        with self.assertRaises(ValueError):import_carrier(self.make(change),self.f.stage)

    def test_environment_is_from_original_options_never_current_app_mode(self):
        def change(body,binding,state,record,snapshot):snapshot['environment']='live'
        with self.assertRaises(ValueError):import_carrier(self.make(change),self.f.stage)

    def test_snapshot_plan_must_be_the_exact_original_prepared_plan(self):
        def change(body,binding,state,record,snapshot):snapshot['plan']=binding['options']
        with self.assertRaisesRegex(ValueError,'native snapshot plan differs from receipt'):
            import_carrier(self.make(change),self.f.stage)

    def test_possible_ink_cannot_be_invented_from_a_clean_raw_stage(self):
        def change(body,binding,state,record,snapshot):state['inkDispatchPossible']=False;snapshot['state']='staged'
        with self.assertRaisesRegex(ValueError,'native dispatch differs from actual raw marker/frontier'):
            import_carrier(self.make(change,terminal=False),self.f.stage)

    def test_missing_original_environment_does_not_gain_task_eligibility_from_envelope(self):
        def change(body,binding,state,record,snapshot):snapshot['environment']='live'
        self.make(change,environment=None);self.interruption_task_bag()
        with self.assertRaisesRegex(ValueError,'interruption claim lacks known exact stage/frontier facts'):
            inspect_result(import_carrier(self.f.bag,self.f.stage))

    def test_exact_source_free_interruption_has_independent_stage_label_eligibility(self):
        self.make();self.interruption_task_bag()
        row=inspect_result(import_carrier(self.f.bag,self.f.stage))['task']['entries'][0]
        self.assertTrue(row['declaredEligible']);self.assertTrue(row['independentTrainingEligibility'])

    def test_current_snapshot_cannot_inherit_eligibility_over_unsupported_or_opaque_predecessor(self):
        pristine=self.f.root/'prior-pristine';shutil.copytree(self.f.bag,pristine)
        for fault in ('required-feature','opaque-profile'):
            self.f.bag=self.f.root/('prior-'+fault);shutil.copytree(pristine,self.f.bag);self.native_chain()
            index=self.f.index();ref=index['attempts'][0];base=self.f.bag/f"data/attempts/{ref['archive']}/{ref['run']}"
            first=parse((base/'1/attempt.json').read_bytes())
            if fault=='required-feature':first['requiredFeatures']=['example.future-prior/1']
            else:first['profile']='example.future-attempt/9'
            raw=json.dumps(first,separators=(',',':')).encode();(base/'1/attempt.json').write_bytes(raw)
            second=parse((base/'2/attempt.json').read_bytes());second['previous']=sha256(raw)
            raw=json.dumps(second,separators=(',',':')).encode();(base/'2/attempt.json').write_bytes(raw)
            index['attempts']=[dict(ref,digest=sha256(raw))];self.f.put_index(index)
            self.interruption_task_bag(eligible=False)
            result=import_carrier(self.f.bag,self.f.stage);summary=inspect_result(result)
            current=next(row for row in summary['nativeBindings'] if row['sequence']==2)
            self.assertFalse(current['selectedRequirementsSupported']);self.assertFalse(current['predecessorProofSupported'])
            self.assertFalse(summary['task']['entries'][0]['independentTrainingEligibility'])

    def test_observation_inventory_cannot_claim_facts_absent_from_exact_terminal(self):
        self.make();pristine=self.f.bag
        for fault in ('observation-present','reason','duplicate','composite-present','missing-composite','wrong-asset'):
            self.f.bag=self.f.root/('availability-'+fault);shutil.copytree(pristine,self.f.bag)
            index=self.f.index();ref=index['attempts'][0];path=self.f.bag/f"data/attempts/{ref['archive']}/{ref['run']}/1/attempt.json"
            snapshot=parse(path.read_bytes());descriptor=next(a for a in index['assets'] if a['object']==snapshot['coverage'])
            coverage=parse((self.f.bag/'data/objects/sha256'/descriptor['object']).read_bytes())
            observation=next(e for e in coverage['entries'] if e['kind']=='adaptiveplotter.observation')
            composite=next(e for e in coverage['entries'] if e['kind']=='adaptiveplotter.observation-composite')
            if fault=='observation-present':observation.clear();observation.update(kind='adaptiveplotter.observation',status='present',asset=coverage['rawTerminal'],classification='accepted')
            elif fault=='reason':observation['reason']='invented-reason'
            elif fault=='duplicate':coverage['entries'].append(copy.deepcopy(observation))
            elif fault=='composite-present':composite.clear();composite.update(kind='adaptiveplotter.observation-composite',status='present',asset=coverage['rawTerminal'])
            elif fault=='missing-composite':coverage['entries'].remove(composite)
            else:observation.clear();observation.update(kind='adaptiveplotter.observation',status='present',asset=coverage['rawAttempt'],classification='accepted')
            raw=json.dumps(coverage,separators=(',',':')).encode();h=sha256(raw);(self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
            index['assets'].append(dict(descriptor,object=h,byteLength=len(raw)));snapshot['coverage']=h
            raw=json.dumps(snapshot,separators=(',',':')).encode();path.write_bytes(raw);index['attempts']=[dict(ref,digest=sha256(raw))];self.f.put_index(index)
            with self.assertRaisesRegex(ValueError,'native observation availability differs from raw owner'):
                import_carrier(self.f.bag,self.f.stage)

    def test_candidate_identity_must_be_the_authored_drawing_digest(self):
        def change(body,binding,state,record,snapshot):body['context']['candidate']['candidateID']='wrong'
        with self.assertRaisesRegex(ValueError,'native candidate authored Drawing identity'):
            import_carrier(self.make(change),self.f.stage)

    def test_self_hashed_other_execution_program_does_not_prove_authored_relation(self):
        self.make(terminal=False)
        index=self.f.index();ref=index['attempts'][0];path=self.f.bag/f"data/attempts/{ref['archive']}/{ref['run']}/1/attempt.json"
        snapshot=parse(path.read_bytes());proposal=parse((self.f.bag/'data/objects/sha256'/snapshot['intent']).read_bytes())
        coverage=parse((self.f.bag/'data/objects/sha256'/snapshot['coverage']).read_bytes());state=parse((self.f.bag/'data/objects/sha256'/coverage['rawAttempt']['object']).read_bytes())
        program=copy.deepcopy(proposal['body']['context']['program']);program['source']['sourceIdentifier']+='|other-drawing'
        from reader import program_digest
        program['contentHash']={'bytes':list(bytes.fromhex(program_digest(program)))}
        proposal['body']['context']['program']=program;proposal['body']['plan']['sourceProgramContentHash']=program['contentHash']
        def asset(value,encoding):
            raw=json.dumps(value,separators=(',',':')).encode();h=sha256(raw);(self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
            d={'object':h,'byteLength':len(raw),'mediaType':'application/json','encoding':encoding};index['assets'].append(d);return d
        plan=asset(proposal['body']['plan'],'adaptiveplotter.local-prepared-plan/1')
        receipt_path=self.f.bag/f"data/jobs/{index['jobs'][0]['engine']}/{index['jobs'][0]['job']}/receipt.json"
        receipt=parse(receipt_path.read_bytes());receipt['preparedPlan']=plan;raw=json.dumps(receipt,separators=(',',':')).encode();receipt_path.write_bytes(raw)
        job=dict(index['jobs'][0],receiptDigest=sha256(raw));index['jobs']=[job]
        proposal['binding']['preparedPlan']=plan;snapshot.update(job=job,plan=plan)
        p=asset(proposal,native.PROPOSAL);state['intent']=dict(proposal['body'],runID=state['intent']['runID'],issuance=proposal['binding'])
        a=asset(state,native.ATTEMPT);coverage['rawAttempt']=a;coverage['entries']=native.observation_entries(None,None)
        for entry in coverage['frontiers'].values():
            if entry['status']=='present':entry['asset']=a
        coverage['rawContent']=sha256(json.dumps({'proposal':p['object'],'attempt':a['object']},sort_keys=True,separators=(',',':')).encode())
        c=asset(coverage,native.COVERAGE);snapshot.update(intent=p['object'],coverage=c['object'])
        raw=json.dumps(snapshot,separators=(',',':')).encode();path.write_bytes(raw);index['attempts']=[dict(ref,digest=sha256(raw))];self.f.put_index(index)
        row=inspect_result(import_carrier(self.f.bag,self.f.stage))['nativeBindings'][0]
        self.assertFalse(row['nativeBindingVerified']);self.assertFalse(row['programRelationSupported'])

    def test_nonterminal_progress_cannot_exceed_plan_even_with_matching_coverage(self):
        def change(body,binding,state,record,snapshot):
            frame=self.progress(body,2);frame['progress']['controllerCompletedStrokeCount']=3;state['progressFrames']=[frame]
        with self.assertRaisesRegex(ValueError,'native progress checkpoint frontier'):
            import_carrier(self.make(change,terminal=False),self.f.stage)

    def test_every_retained_progress_frame_keeps_request_plan_and_frontier_order(self):
        pristine=self.f.root/'progress-pristine';shutil.copytree(self.f.bag,pristine)
        for fault in ('earlier-count','earlier-request','earlier-plan','reverted'):
            self.f.bag=self.f.root/('progress-'+fault);shutil.copytree(pristine,self.f.bag)
            def change(body,binding,state,record,snapshot):
                first=self.progress(body,2);last=self.progress(body,4)
                if fault=='earlier-count':first['progress']['controllerCompletedStrokeCount']=3
                elif fault=='earlier-request':first['progress']['operationID']={'rawValue':'77777777-7777-4777-8777-777777777777'}
                elif fault=='earlier-plan':first['progress']['planRevisionID']={'rawValue':{'bytes':[0]*32}}
                else:first,last=last,first
                state['progressFrames']=[first,last]
            with self.assertRaisesRegex(ValueError,'native progress (request/plan binding|checkpoint frontier)'):
                import_carrier(self.make(change,terminal=False,stroke_count=8),self.f.stage)

    def test_task_original_index_preserves_unknown_fields_and_descriptor_values(self):
        self.task_bag('indexed')
        self.assertEqual(inspect_result(import_carrier(self.f.bag,self.f.stage))['task']['entries'][0]['outcome'],'refused')

    def test_forged_original_index_cannot_change_policy_assets_scope_profile_or_unknown_fields(self):
        self.task_bag();base=self.f.bag
        self.assertIsNotNone(inspect_result(import_carrier(base,self.f.stage))['task'])
        for field in ('requiredFeatures','assets','scope','profile','example.vendor-index'):
            self.f.bag=self.f.root/('source-'+field);shutil.copytree(base,self.f.bag)
            index=self.f.index();task=parse((self.f.bag/'data/objects/sha256'/index['scope']['object']).read_bytes())
            original=parse((self.f.bag/'data/objects/sha256'/task['sourceIndex']['object']).read_bytes())
            actual_original=copy.deepcopy(original)
            self.remove_superseded_wrapper(index,index['scope'],actual_original)
            self.remove_superseded_wrapper(index,task['sourceIndex'],actual_original)
            if field=='requiredFeatures':original[field]=['example.future-policy/1']
            elif field=='assets':original[field]=original[field][1:]
            elif field=='scope':original[field]=dict(original['assets'][0],byteLength=original['assets'][0]['byteLength']+1)
            elif field=='profile':original[field]='example.future-index/9'
            else:original[field]={'preserved':False}
            def add(value,encoding):
                raw=json.dumps(value,separators=(',',':')).encode();h=sha256(raw);(self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
                d={'object':h,'byteLength':len(raw),'mediaType':'application/json','encoding':encoding};index['assets'].append(d);return d
            task['sourceIndex']=add(original,'adaptiveplotter.exchange/1');index['scope']=add(task,'adaptiveplotter.drawing-evidence-task/1');self.f.put_index(index)
            reason={'scope':'asset descriptor disagreement','profile':'task original result profile/kind'}.get(field,'task carrier is not the exact allowed derivation of its original result index')
            with self.assertRaisesRegex(ValueError,'^'+reason+'$'):
                inspect_result(import_carrier(self.f.bag,self.f.stage))

    def test_claim_provenance_is_recomputed_after_an_exact_scope_replacement(self):
        self.task_bag('indexed')
        index=self.f.index();scope=index['scope'];task=parse((self.f.bag/'data/objects/sha256'/scope['object']).read_bytes())
        original=parse((self.f.bag/'data/objects/sha256'/task['sourceIndex']['object']).read_bytes())
        self.remove_superseded_wrapper(index,scope,original)
        task['entries'][0]['claims'][0]['reviewerID']='example.forged-reviewer'
        raw=json.dumps(task,separators=(',',':')).encode();h=sha256(raw);(self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
        index['scope']=dict(scope,object=h,byteLength=len(raw));index['assets'].append(index['scope']);self.f.put_index(index)
        with self.assertRaisesRegex(ValueError,'^task attributed claims differ$'):
            inspect_result(import_carrier(self.f.bag,self.f.stage))

    def test_task_assessment_requires_exact_admitted_typed_identity_and_no_duplicates(self):
        pristine=self.f.root/'assessment-pristine';shutil.copytree(self.f.bag,pristine)
        for mode in ('spoof','unindexed','duplicate'):
            self.f.bag=self.f.root/('assessment-'+mode);shutil.copytree(pristine,self.f.bag)
            self.task_bag(mode)
            with self.assertRaisesRegex(ValueError,'task assessment is not an admitted typed record|duplicate task assessment selection'):
                inspect_result(import_carrier(self.f.bag,self.f.stage))

    def test_known_answer_names_with_wrong_target_contract_remain_uninterpreted_claims(self):
        pristine=self.f.root/'claim-pristine';shutil.copytree(self.f.bag,pristine)
        for mode in ('pruning','choice','admin'):
            self.f.bag=self.f.root/('claim-'+mode);shutil.copytree(pristine,self.f.bag)
            self.task_bag(mode)
            self.assertIsNotNone(inspect_result(import_carrier(self.f.bag,self.f.stage))['task'])

    def test_native_terminal_record_has_a_separate_hard_bound_and_shared_package_budget(self):
        self.make()
        with self.assertRaisesRegex(ValueError,'object size'):
            import_carrier(self.f.bag,self.f.stage,limits=Limits(terminal_record_bytes=64))
        with self.assertRaisesRegex(ValueError,'package materialization budget'):
            import_carrier(self.f.bag,self.f.stage,limits=Limits(materialized_bytes=64))

    @unittest.skipUnless(os.environ.get('ADAPTIVEPLOTTER_RESULT_FIXTURE_OUTPUT'),'Requires actual Swift-exported large native terminal carrier')
    def test_actual_swift_large_terminal_preserves_generic_envelope_bound(self):
        source=Path(os.environ['ADAPTIVEPLOTTER_RESULT_FIXTURE_OUTPUT'])/'native-large-terminal.zip'
        result=import_carrier(source,self.f.stage)
        terminals=[a for a in result.index['assets'] if a['encoding']==native.TERMINAL]
        self.assertTrue(any(a['byteLength']>8*1024**2 for a in terminals));self.assertTrue(result.native_inspections)
        with self.assertRaisesRegex(ValueError,'object size'):
            import_carrier(source,self.f.stage,limits=Limits(terminal_record_bytes=8*1024**2))

    @unittest.skipUnless(os.environ.get('ADAPTIVEPLOTTER_RESULT_FIXTURE_OUTPUT'),'Requires actual Swift observed/rejected native terminal carriers')
    def test_actual_swift_observation_availability_is_bound_to_exact_terminal_asset(self):
        for filename,classification in (('native-observed.zip','accepted'),('native-rejected.zip','rejected')):
            result=import_carrier(Path(os.environ['ADAPTIVEPLOTTER_RESULT_FIXTURE_OUTPUT'])/filename,self.f.stage)
            ref=result.index['attempts'][0]
            snapshot=parse(result.store.read_object(ref['digest']))
            coverage=parse(result.store.read_object(snapshot['coverage']))
            entry=next(e for e in coverage['entries'] if e['kind']=='adaptiveplotter.observation')
            self.assertEqual(entry,{'kind':'adaptiveplotter.observation','status':'present','asset':coverage['rawTerminal'],'classification':classification})
            self.assertEqual(result.native_inspections[0]['observation'],classification)

    def test_native_chain_retains_exact_prefix_when_media_digests_and_counts_are_equal(self):
        pristine=self.f.root/'chain-pristine';shutil.copytree(self.f.bag,pristine)
        for fault in ('baseline','progress','possibleInk'):
            self.f.bag=self.f.root/('chain-'+fault);shutil.copytree(pristine,self.f.bag)
            def change(states):
                if fault=='baseline':states[1]['baselines'][0]['frame']['frameID']='replacement-same-original-bytes'
                elif fault=='progress':states[1]['progressFrames'][0]['media']['frame']['frameID']='replacement-same-frontier'
                else:states[1]['inkDispatchPossible']=False
            self.native_chain(change,progress=fault=='progress')
            with self.assertRaisesRegex(ValueError,'native cumulative (raw (baselines|progressFrames) prefix changed|possible ink cleared)|native dispatch differs|possibleInk reverted'):
                import_carrier(self.f.bag,self.f.stage)

    def test_native_media_cannot_reinterpret_same_bytes_with_different_dimensions_stride_or_orientation(self):
        self.native_chain();base=self.f.bag
        self.assertEqual(len(import_carrier(base,self.f.stage).native_inspections),2)
        for fault in ('reshape','orientation','color'):
            self.f.bag=self.f.root/('media-'+fault);shutil.copytree(base,self.f.bag)
            index=self.f.index();descriptor=next(d for d in index['assets'] if d['encoding']=='raw-gray8')
            if fault=='reshape':
                descriptor['dimensions']={'width':1,'height':4};descriptor['pixelLayout'].update(width=1,height=4,rowStride=1)
            elif fault=='orientation':descriptor['pixelLayout']['orientation']='down'
            else:descriptor['pixelLayout']['colorInterpretation']='sRGB'
            self.f.put_index(index)
            with self.assertRaisesRegex(ValueError,'native original media descriptor differs from exact raw frame'):
                import_carrier(self.f.bag,self.f.stage)

    def test_declared_frontier_cannot_disagree_with_exact_raw_record(self):
        self.make()
        index=self.f.index();ref=index['attempts'][0]
        path=self.f.bag/f"data/attempts/{ref['archive']}/{ref['run']}/1/attempt.json"
        snapshot=parse(path.read_bytes());descriptor=next(a for a in index['assets'] if a['object']==snapshot['coverage'])
        coverage=parse((self.f.bag/'data/objects/sha256'/descriptor['object']).read_bytes())
        coverage['frontiers']['commanded']['count']=0
        raw=json.dumps(coverage,separators=(',',':')).encode();h=sha256(raw)
        (self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
        index['assets'].append(dict(descriptor,object=h,byteLength=len(raw)));snapshot['coverage']=h
        raw=json.dumps(snapshot,separators=(',',':')).encode();path.write_bytes(raw)
        index['attempts']=[dict(ref,digest=sha256(raw))];self.f.put_index(index)
        with self.assertRaises(ValueError):import_carrier(self.f.bag,self.f.stage)

    def test_unknown_native_encoding_remains_opaque_without_binding_permission(self):
        result=import_carrier(self.make(encoding='example.future-native/9'),self.f.stage)
        self.assertEqual(result.native_inspections,[])
        self.assertIn('native intent/coverage/frontier semantics unsupported',result.unsupported)

    @unittest.skipUnless(os.environ.get('DRAWING_NATIVE_TASK_FIXTURE_OUTPUT'),'Requires actual Swift-exported native task carrier')
    def test_actual_swift_result_task_and_coherently_hashed_forgery(self):
        source=Path(os.environ['DRAWING_NATIVE_TASK_FIXTURE_OUTPUT'])/'native-task.zip'
        result=import_carrier(source,self.f.stage);summary=inspect_result(result)
        self.assertTrue(summary['nativeBindings'])
        self.assertEqual(summary['task']['task'],'adaptiveplotter.result-inspection/1')
        self.assertTrue(summary['task']['entries'][0]['declaredEligible'])
        self.assertFalse(summary['task']['entries'][0]['independentTrainingEligibility'])
        for field in ('eligible','sourceIndex','groupingKeys'):
            self.f.bag=self.f.root/('forged-'+field);shutil.copytree(result.staging,self.f.bag)
            index=self.f.index();scope=index['scope'];task=parse((self.f.bag/'data/objects/sha256'/scope['object']).read_bytes())
            original=parse((self.f.bag/'data/objects/sha256'/task['sourceIndex']['object']).read_bytes())
            actual_original=copy.deepcopy(original)
            self.remove_superseded_wrapper(index,scope,actual_original)
            def add(value,encoding):
                raw=json.dumps(value,separators=(',',':')).encode();h=sha256(raw)
                (self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
                asset={'object':h,'byteLength':len(raw),'mediaType':'application/json','encoding':encoding};index['assets'].append(asset);return asset
            if field=='eligible':task['entries'][0]['eligible']=False
            elif field=='groupingKeys':task['entries'][0]['groupingKeys']=[]
            else:
                self.remove_superseded_wrapper(index,task['sourceIndex'],actual_original)
                original['includedAsOf']='2020-01-01T00:00:00Z';task['sourceIndex']=add(original,'adaptiveplotter.exchange/1')
            index['scope']=add(task,'adaptiveplotter.drawing-evidence-task/1');self.f.put_index(index)
            reason={'eligible':'inspection cannot declare training labels','groupingKeys':'task source grouping keys differ','sourceIndex':'task carrier is not the exact allowed derivation of its original result index'}[field]
            with self.assertRaisesRegex(ValueError,'^'+reason+'$'):inspect_result(import_carrier(self.f.bag,self.f.stage))
        interrupted=import_carrier(Path(os.environ['DRAWING_NATIVE_TASK_FIXTURE_OUTPUT'])/'native-interruption-task.zip',self.f.stage)
        facts=inspect_result(interrupted)
        self.assertEqual(facts['task']['task'],'adaptiveplotter.interruption-state/1')
        self.assertTrue(facts['task']['entries'][0]['declaredEligible'])
        self.f.bag=self.f.root/'forged-heldout';shutil.copytree(interrupted.staging,self.f.bag)
        index=self.f.index();scope=index['scope'];task=parse((self.f.bag/'data/objects/sha256'/scope['object']).read_bytes())
        original=parse((self.f.bag/'data/objects/sha256'/task['sourceIndex']['object']).read_bytes())
        self.remove_superseded_wrapper(index,scope,original)
        duplicate=copy.deepcopy(task['entries'][0])
        duplicate['selection'].update(group='different-heldout-group',split='holdout')
        task['entries'].append(duplicate)
        raw=json.dumps(task,separators=(',',':')).encode();h=sha256(raw)
        (self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
        index['scope']=dict(scope,object=h,byteLength=len(raw));index['assets'].append(index['scope']);self.f.put_index(index)
        with self.assertRaisesRegex(ValueError,'^related task evidence crosses groups/splits$'):
            inspect_result(import_carrier(self.f.bag,self.f.stage))

    @unittest.skipUnless(os.environ.get('DRAWING_NATIVE_TASK_FIXTURE_OUTPUT'),'Requires actual Swift canonical Photo/capture-facts task carriers')
    def test_actual_swift_capture_session_and_declared_group_cannot_cross_holdout(self):
        for name in ('session-task.zip','disjoint-task.zip'):
            result=import_carrier(Path(os.environ['DRAWING_NATIVE_TASK_FIXTURE_OUTPUT'])/name,self.f.stage)
            self.assertEqual(len(inspect_result(result)['task']['entries']),2)
            self.f.bag=self.f.root/('group-'+name);shutil.copytree(result.staging,self.f.bag)
            index=self.f.index();scope=index['scope'];task=parse((self.f.bag/'data/objects/sha256'/scope['object']).read_bytes())
            original=parse((self.f.bag/'data/objects/sha256'/task['sourceIndex']['object']).read_bytes())
            task['entries'][1]['selection']['split']='holdout'
            if name=='session-task.zip':task['entries'][1]['selection']['group']='different-group'
            raw=json.dumps(task,separators=(',',':')).encode();h=sha256(raw)
            (self.f.bag/'data/objects/sha256'/h).write_bytes(raw)
            # Keep precisely the allowed source→task transformation, so the
            # negative reaches grouping policy rather than an unrelated extra.
            self.remove_superseded_wrapper(index,scope,original)
            index['scope']=dict(scope,object=h,byteLength=len(raw));index['assets'].append(index['scope']);self.f.put_index(index)
            with self.assertRaisesRegex(ValueError,'related task evidence crosses groups/splits|one declared task group crosses training/holdout splits'):
                inspect_result(import_carrier(self.f.bag,self.f.stage))

    @unittest.skipUnless(os.environ.get('DRAWING_NATIVE_TASK_FIXTURE_OUTPUT'),'Requires actual Swift unknown-source task carriers')
    def test_actual_swift_unknown_input_photo_profiles_and_requirements_supply_no_group_facts(self):
        for kind in ('input-feature','photo-feature','input-profile','photo-profile'):
            result=import_carrier(Path(os.environ['DRAWING_NATIVE_TASK_FIXTURE_OUTPUT'])/('unknown-'+kind+'-task.zip'),self.f.stage)
            rows=inspect_result(result)['task']['entries']
            self.assertTrue(rows and all(not row['independentTrainingEligibility'] for row in rows))
            for drawing in result.index['roots']:
                keys=task_grouping_keys(result,drawing)
                self.assertTrue(any(key.startswith('unknown-input:' if kind.startswith('input') else 'unknown-photo:') for key in keys))
                self.assertFalse(any(key.startswith('capture-session:') for key in keys))
