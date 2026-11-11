"""Independent binding inspection for the three exact native result payloads.

This does not implement physical-plan canonical hashing, registration geometry,
readiness, retry, or a residual-label decoder. Unknown encodings remain opaque.
"""
import json
import uuid
import reader

PROPOSAL = 'adaptiveplotter.drawing-run-proposal/1'
ATTEMPT = 'adaptiveplotter.raw-attempt-state/1'
TERMINAL = 'adaptiveplotter.raw-terminal-record/1'
TERMINAL_JSON_BYTES = 256 * 1024**2
COVERAGE = 'adaptiveplotter.native-coverage/1'
PHYSICAL_LIMIT = 'native physical-plan canonical hash and registration semantics unsupported'
CLOCK_LIMIT = 'Raw monotonic ticks have no declared clock namespace; cross-event elapsed time is unavailable.'


def identity(value):
    if type(value) is dict:
        reader.require(set(value) == {'rawValue'}, 'native UUID wrapper')
        value = value['rawValue']
    reader.require(type(value) is str, 'native UUID')
    try:
        return str(uuid.UUID(value))
    except (ValueError, AttributeError) as error:
        raise ValueError('native UUID') from error


def digest(value):
    if type(value) is str:
        reader.require(len(value) == 64 and all(c in '0123456789abcdef' for c in value), 'native digest')
        return value
    reader.require(type(value) is dict, 'native digest wrapper')
    if set(value) == {'rawValue'}:
        return digest(value['rawValue'])
    reader.require(set(value) == {'bytes'} and type(value['bytes']) is list and len(value['bytes']) == 32, 'native digest bytes')
    for item in value['bytes']:
        reader.integer(item, 0, 255)
    return bytes(value['bytes']).hex()


def ref_equal(left, right):
    return (type(left) is dict and type(right) is dict and
            identity(left['issuer']) == identity(right['issuer']) and
            identity(left['revision']) == identity(right['revision']) and digest(left['digest']) == digest(right['digest']))


def require_extension(store, prior, current):
    """Known snapshots retain the exact owner prefix, not only media digest sets."""
    before = reader.parse(store.read_object(prior['rawAttempt'], store.limits.record_bytes))
    after = reader.parse(store.read_object(current['rawAttempt'], store.limits.record_bytes))
    reader.require(after['intent'] == before['intent'], 'native cumulative intent changed')
    for key in ('baselines', 'progressFrames'):
        old = before.get(key, []); new = after.get(key, [])
        reader.require(len(new) >= len(old) and new[:len(old)] == old, 'native cumulative raw ' + key + ' prefix changed')
    reader.require(not before['inkDispatchPossible'] or after['inkDispatchPossible'], 'native cumulative possible ink cleared')


def observation_entries(record, terminal_asset):
    """The two concrete owner inventory claims derive only from raw terminal JSON."""
    if record is None:
        observation = {'kind': 'adaptiveplotter.observation', 'status': 'unavailable', 'reason': 'No terminal observation was retained at this boundary.'}
    else:
        raw = record['observation']
        reader.require(type(raw) is dict and len(raw) == 1, 'native observation outcome')
        classification = {'observed': 'accepted', 'rejected': 'rejected'}.get(next(iter(raw)))
        if classification is not None:
            reader.require(terminal_asset is not None, 'native observation terminal asset')
            observation = {'kind': 'adaptiveplotter.observation', 'status': 'present', 'asset': terminal_asset, 'classification': classification}
        else:
            reader.require(set(raw) == {'notAttempted'} and type(raw['notAttempted']) is dict and set(raw['notAttempted']) == {'_0'}, 'native unavailable observation reason')
            reason = raw['notAttempted']['_0']
            reader.require(reason in ('requestRefused', 'executionCancelledBeforeObservation', 'executionFailedBeforeObservation', 'frameEvidenceUnavailable', 'projectionOutsideTipApplicability'), 'native unavailable observation reason')
            observation = {'kind': 'adaptiveplotter.observation', 'status': 'unavailable', 'reason': reason}
    attempt = record.get('attemptEvidence', {}) if record is not None else {}
    if attempt.get('mediaCoverage') is not None:
        reader.require(terminal_asset is not None, 'native composite terminal asset')
        composite = {'kind': 'adaptiveplotter.observation-composite', 'status': 'present', 'asset': terminal_asset}
    else:
        reason = attempt.get('missingCoverageReason', 'No derived composite was retained at this boundary.')
        reader.require(type(reason) is str and bool(reason), 'native missing composite reason')
        composite = {'kind': 'adaptiveplotter.observation-composite', 'status': 'unavailable', 'reason': reason}
    return [observation, composite]


def inspect_attempt(store, snapshot, receipt, descriptors, coverage):
    """Return binding facts only for exact known payload encodings.

    Known malformed bytes reject. An unknown payload is preserved and supplies no
    native proof; it is never accepted by a broad type-name/shape exemption.
    """
    intent_descriptor = descriptors[snapshot['intent']]
    if intent_descriptor['encoding'] != PROPOSAL or descriptors[snapshot['coverage']]['encoding'] != COVERAGE:
        return None
    if receipt.get('profile') != 'adaptiveplotter.plot-job-receipt/1' or receipt.get('disposition') not in ('accepted', 'refused'):
        return None
    reader.require(receipt.get('disposition') == 'accepted', 'native accepted receipt')
    reader.require(type(coverage) is dict and coverage.get('profile') == 'adaptiveplotter.coverage/1', 'native coverage')

    def payload(asset, encoding):
        reader.require(type(asset) is dict and asset.get('object') in descriptors, 'native declared payload')
        descriptor = descriptors[asset['object']]
        reader.require(descriptor['encoding'] == encoding and reader.asset_facts(asset) == reader.asset_facts(descriptor), 'native payload descriptor')
        maximum = min(store.limits.terminal_record_bytes, TERMINAL_JSON_BYTES) if encoding == TERMINAL else store.limits.record_bytes
        return reader.parse(store.read_object(asset['object'], maximum), maximum)

    proposal = reader.parse(store.read_object(snapshot['intent'], store.limits.record_bytes))
    reader.require(type(proposal) is dict and set(('body', 'binding')) <= proposal.keys(), 'native proposal')
    body, binding = proposal['body'], proposal['binding']
    reader.require(type(body) is dict and {'requestID','plan','placementID','role','context','recordedAt'} <= body.keys() and type(binding) is dict, 'native proposal body/binding')
    identity(body['placementID']); reader.integer(body['recordedAt']['monotonicNanoseconds'], 0, 2**64-1)
    reader.number(body['recordedAt']['wallTime'])
    reader.require(ref_equal(binding['drawing'], receipt['drawing']) and ref_equal(binding['drawing'], snapshot['drawing']), 'native Drawing binding')
    reader.require({k: identity(binding['job'][k]) for k in ('engine', 'job')} == {k: identity(receipt['handle'][k]) for k in ('engine', 'job')}, 'native job binding')
    client = receipt['client']
    reader.require(identity(binding['key']['namespace']) == identity(client['namespace']) and
                   identity(binding['key']['request']) == identity(client['request']) == identity(body['requestID']) and
                   digest(binding['requestDigest']) == client['requestDigest'] and identity(binding['issuance']) == identity(receipt['issuance']), 'native request/issuance binding')
    reader.require(reader.asset_facts(binding['preparedPlan']) == reader.asset_facts(receipt['preparedPlan']) and
                   reader.asset_facts(binding['options']) == reader.asset_facts(receipt['requestedMediumOptions']), 'native plan/options descriptor binding')
    reader.require(reader.asset_facts(snapshot.get('plan', {})) == reader.asset_facts(receipt['preparedPlan']), 'native snapshot plan differs from receipt')
    if receipt['preparedPlan']['encoding'] != 'adaptiveplotter.local-prepared-plan/1' or receipt['requestedMediumOptions']['encoding'] != 'adaptiveplotter.local-medium-options/1':
        return None
    plan = payload(receipt['preparedPlan'], 'adaptiveplotter.local-prepared-plan/1')
    options = payload(receipt['requestedMediumOptions'], 'adaptiveplotter.local-medium-options/1')
    reader.require(body['plan'] == plan and plan['schemaVersion'] == 1 and
                   digest(binding['physicalPlanID']) == digest(plan['revisionID']) == digest(plan['contentHash']) == digest(binding['physicalPlanHash']), 'native exact physical plan binding')
    reader.require(type(plan['strokes']) is list and len(plan['strokes']) > 0, 'native planned strokes')
    drawing = reader.parse(store.read_object(receipt['drawing']['digest'], store.limits.record_bytes))
    representation = drawing['representation']
    source_program = reader.parse(store.read_object(representation['object'], store.limits.record_bytes))
    reader.validate_program(source_program)
    source_hash = reader.program_digest(source_program)
    reader.require(source_hash == representation['programHash'] == digest(source_program['contentHash']), 'native source program semantic hash')
    context = body['context']; candidate = context['candidate']
    reader.require(ref_equal(candidate['authoredDrawing'], receipt['drawing']) and candidate['sourceProgram'] == source_program and
                   digest(candidate['programContentHash']) == source_hash, 'native exact authored program')
    reader.require(candidate['candidateID'] == receipt['drawing']['digest'] and digest(candidate['contentHash']) == receipt['drawing']['digest'], 'native candidate authored Drawing identity')
    reader.validate_program(context['program'])
    reader.require(reader.program_digest(context['program']) == digest(context['program']['contentHash']) == digest(plan['sourceProgramContentHash']) and
                   identity(context['program']['id']) == identity(plan['sourceProgramID']), 'native execution program binding')
    program_relation_supported = context['program'] == source_program
    state = payload(coverage['rawAttempt'], ATTEMPT)
    intent = state['intent']
    expected_body = {k: v for k, v in intent.items() if k not in ('runID', 'issuance')}
    reader.require(identity(intent['runID']) == identity(snapshot['run']) and expected_body == body and intent.get('issuance') == binding, 'native staged intent differs from pre-motion proposal')
    reader.require(type(state['inkDispatchPossible']) is bool, 'native possible-ink boolean')
    media = [('adaptiveplotter.raw-baseline', item) for item in state['baselines']] + [('adaptiveplotter.raw-progress', item['media']) for item in state.get('progressFrames', [])]
    counts = {'planned': len(plan['strokes'])}
    frames = state.get('progressFrames', [])
    reader.require(type(frames) is list and len(frames) <= 3, 'native progress frame count')
    if frames:
        reader.require(state['inkDispatchPossible'], 'native progress contradicts raw dispatch marker')
    if not state['inkDispatchPossible']:
        counts.update(commanded=0, controllerCompleted=0)
    prior_count = 0
    prior_segments = 0
    planned_segments = None
    checkpoints = {(len(plan['strokes']) * quarter + 3) // 4 for quarter in (1, 2, 3)} if len(plan['strokes']) >= 4 else set()
    for item in frames:
        progress = item['progress']
        reader.require(identity(progress['operationID']) == identity(body['requestID']) and
                       digest(progress['planRevisionID']) == digest(plan['revisionID']), 'native progress request/plan binding')
        planned = reader.integer(progress['plannedStrokeCount'], 1, 0xffffffff)
        commanded = reader.integer(progress['commandedStrokeCount'], 0, 0xffffffff)
        completed = reader.integer(progress['controllerCompletedStrokeCount'], 0, 0xffffffff)
        reader.require(planned == len(plan['strokes']) and 0 <= completed <= commanded <= planned and
                       commanded == completed and completed in checkpoints and completed > prior_count, 'native progress checkpoint frontier')
        expected = plan['strokes'][:completed]
        reader.require([identity(v) for v in progress['completedStrokeIDs']] == [identity(s['logicalStrokeID']) for s in expected] and
                       [identity(v) for v in progress['completedCheckpointIDs']] == [identity(s['endingCheckpointID']) for s in expected] and
                       progress.get('activeStrokeID') is None and progress.get('activeSegmentIndex') is None, 'native progress completed prefix binding')
        segments = reader.integer(progress['plannedSegmentCount'], 1, 0xffffffff)
        submitted = reader.integer(progress['submittedSegmentCount'], 0, 0xffffffff)
        settled = reader.integer(progress['controllerCompletedSegmentCount'], 0, 0xffffffff)
        ack = progress.get('acknowledgedSegmentCount')
        reader.require((planned_segments is None or planned_segments == segments) and
                       prior_segments <= settled == submitted <= segments and commanded <= submitted and
                       (ack is None or reader.integer(ack, 0, 0xffffffff) == settled), 'native progress segment frontier')
        planned_segments = segments; prior_segments = settled; prior_count = completed
        counts.update(commanded=commanded, controllerCompleted=completed)
    terminal = None
    if snapshot['terminalRecord'] is not None:
        descriptor = descriptors[snapshot['terminalRecord']]
        terminal = payload(descriptor, TERMINAL)
        reader.require(terminal['schemaVersion'] == 4 and identity(terminal['runID']) == identity(snapshot['run']) and
                       identity(terminal['requestID']) == identity(body['requestID']), 'native terminal identity')
        reader.require(terminal['role'] == body['role'] and terminal['paper'] == context['paper'] and
                       digest(terminal['plan']['revisionID']) == digest(plan['revisionID']) and
                       digest(terminal['plan']['contentHash']) == digest(plan['contentHash']) and
                       terminal['plan'].get('executionPlan') == plan, 'native terminal plan/context binding')
        attempt = terminal['attemptEvidence']
        reader.require(attempt['intent'] == intent and attempt['baselines'] == state['baselines'] and
                       attempt.get('progressFrames', []) == state.get('progressFrames', []), 'native terminal attempt differs from exact raw component')
        media += [('adaptiveplotter.raw-terminal', item) for item in attempt['terminalFrames']]
        frontiers = terminal['executionFrontiers']
        keys = {'planned': 'plannedStrokeCount', 'commanded': 'commandedStrokeCount',
                'controllerCompleted': 'controllerCompletedStrokeCount', 'inkVerified': 'inkVerifiedStrokeCount'}
        counts = {k: reader.integer(frontiers[v], 0, 0xffffffff) for k, v in keys.items()}
        reader.require(0 <= counts['inkVerified'] <= counts['controllerCompleted'] <= counts['commanded'] <= counts['planned'] == len(plan['strokes']), 'native terminal frontier order')
        disposition = terminal['executionDisposition']; reader.require(type(disposition) is dict and len(disposition) == 1, 'native terminal disposition')
        status = next(iter(disposition)); expected_state = {'completed': 'completed', 'cancelled': 'cancelled', 'failed': 'failed', 'ambiguous': 'failed', 'refused': 'failed'}.get(status)
        reader.require(expected_state is not None and snapshot['state'] == expected_state and snapshot['sealed'], 'native terminal state/seal')
        observation = terminal['observation']; reader.require(type(observation) is dict and len(observation) == 1, 'native observation')
        expected_observation = {'observed': 'accepted', 'rejected': 'rejected', 'notAttempted': 'unavailable'}.get(next(iter(observation)))
        reader.require(expected_observation is not None and expected_observation == snapshot['observation'], 'native observation classification')
        if counts['commanded']:
            reader.require(state['inkDispatchPossible'] and snapshot['dispatch'] == 'possibleInk', 'native commanded frontier contradicts raw dispatch marker')
        if state.get('progressFrames'):
            progress=state['progressFrames'][-1]['progress']
            reader.require(counts['commanded'] >= progress['commandedStrokeCount'] and counts['controllerCompleted'] >= progress['controllerCompletedStrokeCount'], 'native terminal frontier reverted from retained progress')
        reader.require(reader.asset_facts(coverage['rawTerminal']) == reader.asset_facts(descriptor), 'native coverage terminal differs')
    else:
        reader.require(not snapshot['sealed'] and 'rawTerminal' not in coverage and snapshot['observation'] == 'unavailable' and
                       snapshot['state'] == ('interrupted' if state['inkDispatchPossible'] else 'staged'), 'native nonterminal state/seal/terminal')
    expected_dispatch = 'possibleInk' if state['inkDispatchPossible'] or counts.get('commanded', 0) > 0 else 'not-dispatched'
    reader.require(snapshot['dispatch'] == expected_dispatch, 'native dispatch differs from actual raw marker/frontier')
    basis = {'proposal': snapshot['intent'], 'attempt': coverage['rawAttempt']['object']}
    if terminal is not None:
        basis['terminal'] = snapshot['terminalRecord']
    reader.require(coverage.get('rawContent') == reader.sha256(json.dumps(basis, sort_keys=True, separators=(',', ':')).encode()), 'native raw content binding')
    for name in ('planned', 'commanded', 'controllerCompleted', 'inkVerified'):
        declared = coverage['frontiers'][name]
        if name in counts:
            owner = coverage['rawTerminal'] if terminal is not None else coverage['rawAttempt']
            reader.require(declared['status'] == 'present' and reader.integer(declared['count'], 0, 0xffffffff) == counts[name] and reader.asset_facts(declared['asset']) == reader.asset_facts(owner), 'native declared frontier differs from raw owner')
        else:
            reader.require(declared['status'] == 'unavailable' and 'asset' not in declared and 'count' not in declared, 'native unknown frontier was fabricated')
    terminal_asset = coverage.get('rawTerminal')
    for expected in observation_entries(terminal, terminal_asset):
        matching = [entry for entry in coverage['entries'] if entry['kind'] == expected['kind']]
        reader.require(len(matching) == 1 and matching[0] == expected, 'native observation availability differs from raw owner')
    declared_media = [entry for entry in coverage['entries'] if entry['kind'].startswith('adaptiveplotter.raw-')]
    reader.require(len(declared_media) == len(media), 'native original inventory is incomplete')
    known_media = set()
    for (kind, reference), entry in zip(media, declared_media):
        frame = reference['frame']; media_hash = frame['frameSHA256']
        reader.require(media_hash in descriptors and store.object_size(media_hash) == reader.integer(reference['byteCount'], 1, 2**64-1), 'native original media missing/length')
        descriptor = descriptors[media_hash]
        expected_channels = {'gray8': ['gray'], 'rgba8': ['red', 'green', 'blue', 'alpha'], 'bgra8': ['blue', 'green', 'red', 'alpha']}.get(frame['pixelFormat'])
        reader.require(expected_channels is not None, 'native original media channels')
        expected_asset = {'object': media_hash, 'byteLength': reference['byteCount'], 'mediaType': 'application/octet-stream', 'encoding': {'gray8': 'raw-gray8', 'rgba8': 'raw-rgba8', 'bgra8': 'raw-bgra8'}[frame['pixelFormat']]}
        expected_layout = {'width': frame['width'], 'height': frame['height'], 'pixelFormat': {'gray8': 'gray', 'rgba8': 'rgba', 'bgra8': 'bgra'}[frame['pixelFormat']],
            'componentType': 'uint8', 'bitDepth': 8, 'channelOrder': expected_channels, 'rowStride': frame['rowBytes'],
            'byteOrder': 'not-applicable', 'orientation': 'up', 'colorInterpretation': 'linear-gray' if frame['pixelFormat'] == 'gray8' else 'sRGB'}
        reader.require(reader.asset_facts(descriptor) == dict(expected_asset, dimensions={'width': frame['width'], 'height': frame['height']}, pixelLayout=expected_layout), 'native original media descriptor differs from exact raw frame')
        reader.require(type(frame['frameID']) is str and bool(frame['frameID']) and entry['kind'] == kind and entry['status'] == 'present' and reader.asset_facts(entry['asset']) == expected_asset and entry['rawFrameID'] == frame['frameID'] and entry['rawCaptureTicks'] == str(frame['captureNanoseconds']) and entry['captureClock'] == 'unavailable' and 'captureTime' not in entry, 'native original reference differs from raw component')
        known_media.add(media_hash)
    environment = options.get('environment')
    reader.require(environment is None or environment in ('live', 'simulation'), 'native environment option')
    if environment is not None:
        reader.require(snapshot['environment'] == environment, 'native environment differs from original options')
    return {'nativeBindingVerified': program_relation_supported, 'programRelationSupported': program_relation_supported, 'physicalPlanCanonicalHashVerified': False,
            'archive': snapshot['issuerArchive'], 'run': snapshot['run'], 'sequence': snapshot['sequence'],
            'job': snapshot['job'], 'drawing': snapshot['drawing'], 'environment': environment,
            'state': snapshot['state'], 'observation': snapshot['observation'], 'dispatch': snapshot['dispatch'],
            'frontiers': counts, 'rawAttempt': coverage['rawAttempt']['object'], 'originalMedia': sorted(known_media),
            'selectedRequirementsSupported': not snapshot.get('requiredFeatures') and not receipt.get('requiredFeatures') and not coverage.get('requiredFeatures') and not drawing.get('requiredFeatures'),
            'limitations': [PHYSICAL_LIMIT, CLOCK_LIMIT] + ([] if environment is not None else ['Raw execution environment was not retained.']) +
                ([] if program_relation_supported else ['Native execution-program compositor relation is unsupported; authored-to-execution geometry is unproved.'])}
