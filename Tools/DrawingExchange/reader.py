"""Independent bounded authored-record reader; no Swift process or media decoding.

Checksums establish integrity, never authentication. This is the DX02 record
reader, not the DX03 BagIt/archive importer: encoded image header/dimension and
expansion proof, manifest/path closure, and atomic installation remain DX03.
Original record/program bytes are returned without JSON reserialization.
"""
import hashlib, json, math, re, struct, unicodedata, uuid
from pathlib import Path

def require(condition, message):
    if not condition: raise ValueError(message)
def sha256(data): return hashlib.sha256(data).hexdigest()
def unique(pairs):
    out = {}
    for k,v in pairs:
        require(k not in out, "duplicate key")
        out[k] = v
    return out
def parse(data, maximum=8*1024*1024):
    require(len(data) <= maximum and not data.startswith(b"\xef\xbb\xbf"), "JSON bounds/BOM")
    def finite(value):
        n=float(value); require(math.isfinite(n), "nonfinite number"); return n
    def invalid(value): raise ValueError("nonfinite constant")
    try:
        value = json.loads(data.decode("utf8"), object_pairs_hook=unique, parse_float=finite, parse_constant=invalid)
        def bounded(v, depth=0):
            require(depth <= 64, "JSON depth")
            if isinstance(v, dict):
                for k, x in v.items(): k.encode("utf8"); bounded(x, depth+1)
            elif isinstance(v, list):
                for x in v: bounded(x, depth+1)
            elif isinstance(v, str): v.encode("utf8")
            elif type(v) in (int, float): require(math.isfinite(v), "nonfinite number")
        bounded(value)
        return value
    except (UnicodeError, RecursionError, OverflowError) as error:
        raise ValueError("invalid JSON scalar/depth") from error

def program_digest(program):
    """Independent port of DrawingProgramHashBasis + CanonicalEncoder schema 1.

    Match Sources/PlotterModel/{CanonicalEncoding,DrawingProgram,Geometry}.swift:
    big endian integers/finite doubles, NFC UTF-8 strings with UInt32 lengths,
    raw UUID bytes, ordered strokes. contentHash is NOT part of its own basis.
    """
    encoded = bytearray(b"APCB" + struct.pack(">H", 1))

    def integer(value, code, maximum):
        require(type(value) is int and 0 <= value <= maximum, "invalid APCB integer")
        encoded.extend(struct.pack(code, value))

    def count(value):
        integer(value, ">I", 0xffffffff)

    def double(value):
        require(type(value) in (int, float) and math.isfinite(value),
                "invalid APCB double")
        encoded.extend(struct.pack(">d", 0.0 if value == 0 else value))

    def string(value):
        require(type(value) is str, "invalid APCB string")
        raw = unicodedata.normalize("NFC", value).encode("utf-8")
        count(len(raw))
        encoded.extend(raw)

    def identity(value):
        require(set(value) == {"rawValue"}, "invalid strong ID")
        encoded.extend(uuid.UUID(value["rawValue"]).bytes)

    string("DrawingProgram")
    identity(program["id"])
    integer(program["schemaVersion"], ">H", 0xffff)
    require(program["schemaVersion"] == 1, "unsupported program schema")
    extent = program["fieldExtent"]
    double(extent["width"])
    double(extent["height"])
    strokes = sorted(program["strokes"], key=lambda stroke: stroke["ordering"])
    count(len(strokes))
    for stroke in strokes:
        identity(stroke["id"])
        points = stroke["path"]["points"]
        count(len(points))
        for point in points:
            double(point["x"])
            double(point["y"])
        double(stroke["style"]["nominalLineWidth"])
        identity(stroke["style"]["penProfileID"])
        integer(stroke["semanticRole"], ">B", 0xff)
        integer(stroke["ordering"], ">I", 0xffffffff)
    string(program["source"]["kind"])
    string(program["source"]["sourceIdentifier"])
    return sha256(encoded)


SAFE = 9007199254740991

def integer(v, minimum=0, maximum=SAFE):
    require(type(v) is int and minimum <= v <= maximum, "integer range/type")
    return v

def number(v, positive=False):
    require(type(v) in (int, float) and math.isfinite(v) and (not positive or v > 0), "finite number")
    return v

def uuid_text(v, canonical=True):
    require(type(v) is str, "UUID type")
    try: parsed = uuid.UUID(v)
    except (ValueError, AttributeError): raise ValueError("UUID")
    require(not canonical or str(parsed) == v, "UUID spelling")
    return parsed

def object_bytes(root, digest, maximum=None):
    require(type(digest) is str and re.fullmatch(r"[0-9a-f]{64}", digest), "object digest")
    path = root / "objects" / digest
    require(not path.is_symlink(), "object symlink")
    if maximum is not None: require(path.stat().st_size <= maximum, "object size")
    raw = path.read_bytes()
    require(sha256(raw) == digest, "object hash")
    return raw

def timestamp(value):
    require(isinstance(value, dict) and ("wallTime" in value or "event" in value), "timestamp")
    if "wallTime" in value: walltime(value["wallTime"])
    if "event" in value:
        e=value["event"]
        require(type(e["clockID"]) is str and bool(e["clockID"]), "clock ID")
        uuid_text(e["bootSession"])
        require(type(e["ticks"]) is str and re.fullmatch(r"0|[1-9][0-9]*", e["ticks"]), "clock ticks")
        integer(e["ticksPerSecond"], 1)

def walltime(value):
    # RFC3339 permits offsets, fractional seconds, and leap seconds.
    import datetime
    require(type(value) is str and re.fullmatch(r"\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[Zz]|[+-]\d{2}:\d{2})", value), "wall time")
    normalized = value.upper().replace("Z", "+00:00")
    require(int(normalized[17:19]) <= 60, "wall seconds")
    datetime.datetime.fromisoformat(normalized[:17] + ("59" if normalized[17:19] == "60" else normalized[17:19]) + normalized[19:])

def features(record, supported):
    values=record["requiredFeatures"]
    require(isinstance(values,list) and all(type(v) is str and re.fullmatch(r"[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+(?:[/:][A-Za-z0-9._/-]+)?",v) for v in values), "features")
    require(len(set(values)) == len(values), "duplicate features")
    return set(values)-set(supported)

def load_record(root, ref, depth=0):
    require(depth <= 64, "closure depth")
    require(set(ref) == {"issuer","revision","digest"}, "reference fields")
    for k in ("issuer","revision"): uuid_text(ref[k])
    raw = object_bytes(root, ref["digest"], 8*1024*1024)
    record = parse(raw)
    require(record["ref"] == {k:ref[k] for k in ("issuer","revision")}, "identity mismatch")
    return record, raw

def validate_program(program):
    def identity(v):
        require(isinstance(v,dict) and set(v)=={"rawValue"}, "strong ID")
        return uuid_text(v["rawValue"], canonical=False)
    identity(program["id"])
    require(type(program["schemaVersion"]) is int and program["schemaVersion"] == 1, "program schema")
    extent=program["fieldExtent"]
    number(extent["width"],True); number(extent["height"],True)
    strokes=program["strokes"]
    require(isinstance(strokes,list) and 0 < len(strokes) <= 100000, "stroke count")
    ids=[]; order=[]; count=0
    for s in strokes:
        ids.append(identity(s["id"])); order.append(integer(s["ordering"],0,0xffffffff))
        integer(s["semanticRole"],0,1)
        number(s["style"]["nominalLineWidth"],True);identity(s["style"]["penProfileID"])
        points=s["path"]["points"]; require(isinstance(points,list) and len(points)>=2,"polyline count")
        count+=len(points);require(count<=2000000,"point count")
        xy=[]
        for p in points:
            x=number(p["x"]);y=number(p["y"])
            require(0<=x<=extent["width"] and 0<=y<=extent["height"],"point bounds");xy.append((x,y))
        require(any(a!=b for a,b in zip(xy,xy[1:])),"degenerate polyline")
    require(len(set(ids))==len(ids) and len(set(order))==len(order),"duplicate strokes/order")
    for k in ("kind","sourceIdentifier"):
        require(type(program["source"][k]) is str and bool(program["source"][k]),"source provenance")
    h=program["contentHash"]["bytes"]
    require(isinstance(h,list) and len(h)==32,"digest length")
    for b in h:integer(b,0,255)

def declaration(link):
    allowed={"none":{"state"},"present":{"state","ref"},"unavailable":{"state","reason","knownRef"}}
    state=link["state"]
    require(state in allowed and set(link)<=allowed[state],"link fields")
    if state=="present": require("ref" in link,"missing ref")
    if state=="unavailable":
        require(type(link.get("reason")) is str and bool(link["reason"]),"unavailable reason")
        if "knownRef" in link:
            ref=link["knownRef"];require(set(ref)=={"issuer","revision","digest"},"known ref")
            uuid_text(ref["issuer"]);uuid_text(ref["revision"])
            require(re.fullmatch(r"[0-9a-f]{64}",ref["digest"]),"known digest")
    return state

def drawing(root, ref, depth=0, *, asset_descriptors=None, supported_features=()):
    record, raw = load_record(root, ref, depth)
    if record["profile"] != "adaptiveplotter.drawing/1": return {"opaque":True,"bytes":raw,"blocked":True}
    walltime(record["createdAt"])
    unsupported=features(record,supported_features)
    r=record["representation"]
    # Integrity still applies when representation semantics are unsupported.
    program_raw=object_bytes(root,r["object"],128*1024*1024)
    if r["kind"]!="adaptiveplotter.stroke-program/1": return {"opaque":True,"bytes":raw,"blocked":True}
    program=parse(program_raw,128*1024*1024);validate_program(program)
    digest=program_digest(program)
    require(digest==r["programHash"]==bytes(program["contentHash"]["bytes"]).hex(),"APCB mismatch")
    if "nominalPenWidthMillimeters" in r: number(r["nominalPenWidthMillimeters"],True)
    if "intendedPhysicalFieldMillimeters" in r:
        field=r["intendedPhysicalFieldMillimeters"]
        require(isinstance(field,dict),"physical field")
        number(field["width"],True);number(field["height"],True)
    if "historicalUnits" in r:
        historical=r["historicalUnits"]
        require(isinstance(historical,dict) and historical.get("state") in ("known","unknown"),"historical units state")
        if historical["state"]=="unknown":
            require("units" not in historical and "producerReceipt" not in historical,"unknown historical units contradiction")
        else:
            require(type(historical.get("units")) is str and bool(historical["units"]),"historical units claim")
            # Membership edits retain the validated parent's original unit proof.
            # Their completed producer validation below checks unchanged units;
            # recursively admitted ancestors anchor that proof to its producer.
            membership=record['producer']['id']=='adaptiveplotter.stroke-membership' and record['producer']['version']=='1'
            if not membership:
                require(historical.get("producerReceipt")==record["producer"]["record"],"historical unit receipt")
    strokes=sorted(program["strokes"],key=lambda s:s["ordering"])
    producer=record["producer"]
    require(type(producer["id"]) is str and re.fullmatch(r"[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+(?:[/:][A-Za-z0-9._/-]+)?",producer["id"]) and type(producer["version"]) is str and bool(producer["version"]),"producer")
    receipt=parse(object_bytes(root,producer["record"],8*1024*1024))
    known=record["producer"]["id"]=="adaptiveplotter.catalog" and record["producer"]["version"]=="1"
    if known: validate_catalog(record,receipt,program)
    source_supported=True
    dependency_reasons=[]; dependency_records=[]; dependency_features=set(); parent_result=None
    for name in ("input","parent"):
        link=record[name];state=declaration(link)
        if state=="unavailable":
            source_supported=False;dependency_reasons.append(name+": unavailable")
        if state=="present":
            if name=="parent": child=drawing(root,link["ref"],depth+1,asset_descriptors=asset_descriptors,supported_features=supported_features)
            else: child=image_input(root,link["ref"],depth+1,asset_descriptors=asset_descriptors,supported_features=supported_features)
            if name=="parent": parent_result=child
            dependency_records.append(child)
            dependency_features.update(child.get("unsupportedFeatures",()))
            child_supported=child.get("sourceSupported",not child.get("blocked",False)) and not child.get("blocked",False)
            if not child_supported:
                source_supported=False;dependency_reasons.append(name+": unsupported source semantics")
                dependency_reasons.extend(name+": "+reason for reason in child.get("dependencyReasons",()))
    if producer['id']=='adaptiveplotter.stroke-membership' and producer['version']=='1':
        validate_membership(root,record,receipt,program,parent_result,depth,
                            asset_descriptors=asset_descriptors,supported_features=supported_features)
        known=True
    geometry_supported=not bool(unsupported)
    # Dependency semantics gate only consumers that need those semantics.
    # These are format-level permissions, never current physical readiness.
    capabilities={"preview":geometry_supported,"plot":geometry_supported,"edit":geometry_supported,
                  "regenerate":False,"train":False}
    return {"bytes":raw,"programBytes":program_raw,"programHash":digest,"points":[[p["x"],p["y"]] for s in strokes for p in s["path"]["points"]],
            "producerVerified":known,"unsupportedFeatures":sorted(unsupported),"unsupportedDependencyFeatures":sorted(dependency_features),
            "blocked":not geometry_supported,"sourceSupported":source_supported,"sourceSemanticsSupported":source_supported,
            "unsupportedRequiredFeatures":sorted(unsupported),"unsupportedSourceDependencies":dependency_reasons,"dependencyReasons":dependency_reasons,
            "dependencies":dependency_records,"capabilities":capabilities}

def validate_membership(root, record, claim, program, parent_result, depth, *, asset_descriptors, supported_features):
    """Verify the built-in membership producer, independently of Swift admission."""
    required={'profile','action','strokeIDs','parent','universe','before','after'}
    require(isinstance(claim,dict) and required<=claim.keys(), 'membership receipt fields')
    require(claim['profile']=='adaptiveplotter.stroke-membership/1' and
            record['parent']['state']=='present' and parent_result is not None and
            not parent_result.get('opaque',False), 'membership parent/profile')
    parent_ref=record['parent']['ref']
    parent=parse(parent_result['bytes']); before=parse(parent_result['programBytes'],128*1024*1024)
    require(claim['parent']==parent_ref and claim['before']==parent_result['programHash'] and
            claim['after']==program_digest(program) and record['input']==parent['input'],
            'membership receipt bindings')
    require(set(parent['requiredFeatures'])<=set(record['requiredFeatures']), 'membership required features')

    def units(owner):
        r=owner['representation']; historical=r.get('historicalUnits',{})
        field=r.get('intendedPhysicalFieldMillimeters')
        return (r.get('nominalPenWidthMillimeters'),
                None if field is None else (field['width'],field['height']),
                unicodedata.normalize('NFC',historical['units']) if historical.get('state')=='known' else None,
                historical.get('producerReceipt') if historical.get('state')=='known' else None)
    require(units(record)==units(parent), 'membership units')
    producer=parent['producer']
    if producer['id']=='adaptiveplotter.stroke-membership' and producer['version']=='1':
        expected_universe=parse(object_bytes(root,producer['record'],8*1024*1024))['universe']
    else: expected_universe=parent_ref
    require(claim['universe']==expected_universe, 'membership universe binding')
    universe_result=parent_result if expected_universe==parent_ref else drawing(
        root,expected_universe,depth+1,asset_descriptors=asset_descriptors,supported_features=supported_features)
    require(not universe_result.get('opaque',False), 'membership universe semantics')
    universe=parse(universe_result['programBytes'],128*1024*1024)

    def identity(value):
        require(isinstance(value,dict) and set(value)=={'rawValue'}, 'membership stroke ID')
        return uuid_text(value['rawValue'],canonical=False)
    def stroke(s):
        return (identity(s['id']),tuple((p['x'],p['y']) for p in s['path']['points']),
                s['style']['nominalLineWidth'],identity(s['style']['penProfileID']),s['semanticRole'],s['ordering'])
    def extent(p): return (p['fieldExtent']['width'],p['fieldExtent']['height'])
    def source(p): return tuple(unicodedata.normalize('NFC',p['source'][k]) for k in ('kind','sourceIdentifier'))
    all_strokes=sorted(universe['strokes'],key=lambda s:s['ordering'])
    all_by_id={identity(s['id']):stroke(s) for s in all_strokes}
    require(extent(before)==extent(universe) and
            all(all_by_id.get(identity(s['id']))==stroke(s) for s in before['strokes']), 'membership parent geometry')
    require(isinstance(claim['strokeIDs'],list), 'membership stroke IDs')
    ids=[identity(s) for s in claim['strokeIDs']]; selected=set(ids)
    require(len(selected)==len(ids) and selected<=all_by_id.keys(), 'membership duplicate/unknown stroke')
    current={identity(s['id']) for s in before['strokes']}
    action=claim['action']
    require(action in ('remove','restore','membership'), 'membership action')
    if action=='remove':
        require(bool(selected) and selected<=current, 'membership remove/no change')
        target=current-selected
    elif action=='restore':
        require(bool(selected) and selected.isdisjoint(current), 'membership restore/no change')
        target=current|selected
    else: target=selected
    require(bool(target) and target!=current, 'membership empty/no change')
    expected=[stroke(s) for s in all_strokes if identity(s['id']) in target]
    actual=[stroke(s) for s in sorted(program['strokes'],key=lambda s:s['ordering'])]
    require(actual==expected and extent(program)==extent(before) and source(program)==source(before), 'membership geometry')

def asset(root, descriptor, asset_descriptors=None, dimensions=None):
    extra=(asset_descriptors or {}).get(descriptor["object"],{})
    require(all(k not in descriptor or descriptor[k]==v for k,v in extra.items()),"descriptor contradiction")
    d={**extra,**descriptor};integer(d["byteLength"])
    require(type(d["mediaType"]) is str and re.fullmatch(r"[^\s/]+/[^\s/]+",d["mediaType"]) and type(d["encoding"]) is str and bool(d["encoding"]),"asset types")
    raw=object_bytes(root,d["object"],32*1024*1024)
    require(len(raw)==d["byteLength"],"asset length")
    for expected in (dimensions,d.get("dimensions")):
        if expected is not None:
            require(set(expected)=={"width","height"},"dimension fields")
            for v in expected.values():integer(v,1,8192)
            require(expected["width"]*expected["height"]<=32*1024*1024,"image pixels")
    layout=d.get("pixelLayout")
    known=d["encoding"] in ("raw-gray8","raw-rgb8","raw-rgba8","raw-bgra8")
    if d["encoding"].startswith("raw-"): require(layout is not None,"raw pixelLayout required")
    supported=known
    if layout is not None:
        for k in ("width","height","bitDepth","rowStride"):integer(layout[k],1)
        require(layout["width"]<=8192 and layout["height"]<=8192 and layout["width"]*layout["height"]<=32*1024*1024 and layout["bitDepth"]<=64,"layout dimensions/depth")
        for k in ("pixelFormat","componentType","orientation","colorInterpretation"):
            require(type(layout[k]) is str and bool(layout[k]),"layout string")
        channels=layout["channelOrder"]
        require(isinstance(channels,list) and 0<len(channels)<=16 and all(type(x) is str and bool(x) for x in channels),"channels")
        require(layout["byteOrder"] in ("little","big","not-applicable"),"byte order")
        row=(layout["width"]*len(channels)*layout["bitDepth"]+7)//8
        size=layout["rowStride"]*layout["height"]
        require(row<=layout["rowStride"] and size<=SAFE and size==len(raw),"stride/length overflow")
        dims={k:layout[k] for k in ("width","height")}
        for expected in (dimensions,d.get("dimensions")):
            if expected is not None: require(dims==expected,"asset dimensions")
        expected_channels={"gray":["gray"],"rgb":["red","green","blue"],"rgba":["red","green","blue","alpha"],"bgra":["blue","green","red","alpha"]}.get(layout["pixelFormat"])
        if known:
            expected_format={"raw-gray8":"gray","raw-rgb8":"rgb","raw-rgba8":"rgba","raw-bgra8":"bgra"}[d["encoding"]]
            expected_order={"gray":["gray"],"rgb":["red","green","blue"],"rgba":["red","green","blue","alpha"],"bgra":["blue","green","red","alpha"]}[expected_format]
            require(layout["bitDepth"]==8 and layout["componentType"]=="uint8" and layout["pixelFormat"]==expected_format and channels==expected_order,"known raw encoding/layout disagreement")
        supported &= layout["componentType"]=="uint8" and layout["bitDepth"]==8 and channels==expected_channels and layout["orientation"] in ("up","down","left","right","up-mirrored","down-mirrored","left-mirrored","right-mirrored") and layout["colorInterpretation"] in ("linear-gray","sRGB")
    if d["encoding"].startswith("array-"):require("arrayLayout" in d,"arrayLayout required")
    if "arrayLayout" in d:
        a=d["arrayLayout"];require(isinstance(a["shape"],list) and 0<len(a["shape"])<=16,"array shape")
        product=1
        for n in a["shape"]:product*=integer(n,1);require(product<=SAFE,"array overflow")
        require(a["layout"] in ("row-major","column-major") and a["byteOrder"] in ("little","big","not-applicable"),"array layout")
        for k in ("dtype","units"):require(type(a[k]) is str and bool(a[k]),"array fact")
        widths={"uint8":1,"int8":1,"uint16":2,"int16":2,"float16":2,"uint32":4,"int32":4,"float32":4,"uint64":8,"int64":8,"float64":8}
        if a["dtype"] in widths:require(product*widths[a["dtype"]]<=SAFE and product*widths[a["dtype"]]==len(raw),"array byte length")
        if d["encoding"].startswith("array-"):supported=a["dtype"] in widths
    return supported

def image_input(root, ref, depth=0, *, asset_descriptors=None, supported_features=()):
    value,raw=load_record(root,ref,depth)
    if value["profile"]!="adaptiveplotter.image-input/1":
        return {"bytes":raw,"opaque":True,"blocked":True,"sourceSupported":False,"dependencyReasons":["unsupported ImageInput profile"]}
    unsupported=features(value,supported_features)
    photo,photo_raw=load_record(root,value["photo"],depth+1)
    reasons=[];supported=True
    if photo["profile"]!="adaptiveplotter.photo/1":
        supported=False;reasons.append("unsupported Photo profile")
    else:
        unsupported.update(features(photo,supported_features))
        for name in ("acquired","imported"):
            fact=photo[name];require(fact["state"] in ("known","unknown") and type(fact["provenance"]) is str and bool(fact["provenance"]),"dated fact")
            require(("time" in fact)==(fact["state"]=="known"),"dated fact contradiction")
            if "time" in fact:timestamp(fact["time"])
        if "captureFacts" in photo:asset(root,photo["captureFacts"],asset_descriptors)
        supported=asset(root,photo["original"],asset_descriptors,photo["dimensions"])
        if not supported:reasons.append("unsupported original encoding/layout or encoded-media proof pending DX03")
    basis=value["pixelBasis"];dims=basis["dimensions"]
    for n in dims.values():integer(n,1)
    require(set(dims)=={"width","height"} and dims["width"]<=8192 and dims["height"]<=8192 and dims["width"]*dims["height"]<=32*1024*1024,"input dimensions")
    require(all(basis[k]==v for k,v in {"origin":"top-left","xAxis":"right","yAxis":"down","pixelEdges":"integer","pixelCenters":"half-integer"}.items()),"pixel basis")
    supported &= basis["orientation"] in ("up","down","left","right","up-mirrored","down-mirrored","left-mirrored","right-mirrored")
    supported &= asset(root,value["raster"],asset_descriptors,dims)
    for matrix in (value["sourceToInput"],value["inputToField"]):
        require(isinstance(matrix,list) and len(matrix)==9,"transform")
        for n in matrix:number(n)
    mask=value["mask"];require(mask["state"] in ("none","present") and set(mask)==({"state"} if mask["state"]=="none" else {"state","asset"}),"mask")
    if mask["state"]=="present":supported &= asset(root,mask["asset"],asset_descriptors,dims)
    require(isinstance(value["operations"],list) and 0<len(value["operations"])<=1024,"operations")
    for operation in value["operations"]:
        asset(root,operation["parameters"],asset_descriptors)
        if operation["kind"] not in ("identity","crop","rotate","scale","mask"):supported=False
        require(operation["kind"]!="mask" or mask["state"]=="present","missing mask")
    preparation=value["preparation"]
    require(type(preparation["id"]) is str and re.fullmatch(r"[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+(?:[/:][A-Za-z0-9._/-]+)?",preparation["id"]) and type(preparation["version"]) is str and bool(preparation["version"]),"preparation producer")
    parse(object_bytes(root,preparation["record"],8*1024*1024))
    source_supported=not bool(unsupported) and supported
    if unsupported:reasons.append("unknown required source features")
    if not supported and not reasons:reasons.append("unsupported source encoding/orientation/operation or encoded-media proof pending DX03")
    return {**value,"bytes":raw,"photoBytes":photo_raw,"unsupportedFeatures":sorted(unsupported),
            "blocked":not source_supported,"sourceSupported":source_supported,"dependencyReasons":reasons}

def validate_catalog(record, receipt, program):
    require(record['input']['state']=='none' and record['parent']['state']=='none','catalog source-free')
    require(receipt.get('profile') in ('adaptiveplotter.catalog-receipt/1','adaptiveplotter.example.catalog-receipt/1'),'catalog profile')
    policy=receipt.get('tessellation',{'maximumChordError':0.25,'algorithmRevision':1,'maximumSegments':4096})
    error=number(policy['maximumChordError'],True)
    require(type(policy['algorithmRevision']) is int and policy['algorithmRevision']==1,'tessellation revision')
    maximum=integer(policy['maximumSegments'],12,0xffffffff)
    if 'nominalPenWidthMillimeters' in receipt:number(receipt['nominalPenWidthMillimeters'],True)
    require(receipt.get('nominalPenWidthMillimeters')==record['representation'].get('nominalPenWidthMillimeters'),'catalog units')
    representation=record['representation']
    for owner in (receipt,representation):
        if 'intendedPhysicalFieldMillimeters' in owner:
            field=owner['intendedPhysicalFieldMillimeters']
            require(isinstance(field,dict),'catalog physical field type')
            number(field['width'],True);number(field['height'],True)
    claimed=receipt.get('intendedPhysicalFieldMillimeters')
    declared=representation.get('intendedPhysicalFieldMillimeters')
    require((claimed is None and declared is None) or (claimed is not None and declared is not None and all(claimed[k]==declared[k] for k in ('width','height'))),'catalog intended physical field')
    historical=representation.get('historicalUnits')
    if historical is not None and historical['state']=='known':
        require(type(receipt.get('historicalUnits')) is str and receipt['historicalUnits']==historical['units'] and historical['producerReceipt']==record['producer']['record'],'unproven catalog historical units')

    entry=receipt['entry']; extent=(100,100)
    paths={
      'line':[[(5,50),(95,50)]],
      'polyline':[[(5,80),(28,20),(50,78),(72,20),(95,80)]],
      'rectangle':[[(2,2),(98,2),(98,68),(2,68),(2,2)]],
      'square':[[(2,2),(98,2),(98,98),(2,98),(2,2)]],
      'triangle':[[(50,2),(98,98),(2,98),(50,2)]],
      'pyramid':[[(5,66),(50,92),(95,66),(50,49),(5,66)],[(50,5),(5,66)],[(50,5),(50,49)],[(50,5),(95,66)]],
      'elephant':[[(18,54),(22,33),(41,19),(80,18),(97,27),(107,25),(119,31),(124,44),(122,70),(115,85),(107,85),(108,57),(98,52),(92,59),(90,85),(80,85),(78,60),(53,60),(51,85),(41,85),(39,59),(28,68),(18,62),(18,54)],[(87,29),(104,32),(101,52),(89,48),(87,29)],[(111,58),(121,54)],[(108,37),(110,37)],[(21,34),(10,23),(7,28)]],
      'metricSquare40':[[(0,0),(40,0),(40,40),(0,40),(0,0)],[(0,0),(40,40)],[(40,0),(0,40)]],
      'metricRectangle40x20':[[(0,0),(40,0),(40,20),(0,20),(0,0)]]}
    if entry in ('regularPolygon','star'):
        count=6 if entry=='regularPolygon' else 10
        points=[]
        for i in range(count):
            radius=48 if i%2==0 or entry=='regularPolygon' else 21
            angle=-math.pi/2+2*math.pi*i/count
            points.append((50+radius*math.cos(angle),50+radius*math.sin(angle)))
        paths[entry]=[points+[points[0]]]
    if entry in ('circle','ellipse'):
        count=max(12,math.ceil(2*math.pi*math.sqrt(48/(8*error))))
        require(count<=maximum,'excessive tessellation')
        height=96 if entry=='circle' else 66;cy=50 if entry=='circle' else 35
        points=[(50+48*math.cos(2*math.pi*i/count),cy+height/2*math.sin(2*math.pi*i/count)) for i in range(count)]
        paths[entry]=[points+[points[0]]]
    require(entry in paths,'catalog entry')
    extent={'rectangle':(100,70),'ellipse':(100,70),'elephant':(140,100),'metricSquare40':(40,40),'metricRectangle40x20':(40,20)}.get(entry,extent)
    require(program['fieldExtent']==dict(zip(('width','height'),extent)),'catalog extent')
    source='adaptiveplotter.builtin.'+entry+'.v1'
    if entry in ('circle','ellipse'): source+='.tess-1-'+struct.pack('>d',error).hex()+'-'+str(maximum)
    require(receipt['sourceIdentifier']==source and program['source']=={'kind':'built-in-vector-catalog','sourceIdentifier':source},'catalog source')
    strokes=sorted(program['strokes'],key=lambda s:s['ordering'])
    require(len(strokes)==len(paths[entry]),'catalog stroke count')
    # Stable IDs use a SHA256-derived UUID, exactly as the catalog owner does.
    style=strokes[0]['style']
    style_bytes=b'APCB\x00\x01'+struct.pack('>d',style['nominalLineWidth'])+uuid.UUID(style['penProfileID']['rawValue']).bytes
    seed='program:'+source+':'+sha256(style_bytes)
    def stable(seed):
        b=bytearray(hashlib.sha256(seed.encode()).digest()[:16]);b[6]=(b[6]&15)|80;b[8]=(b[8]&63)|128
        return uuid.UUID(bytes=bytes(b))
    require(uuid.UUID(program['id']['rawValue'])==stable(seed),'catalog program ID')
    for i,(stroke,expected) in enumerate(zip(strokes,paths[entry])):
        actual=[(p['x'],p['y']) for p in stroke['path']['points']]
        require(actual==expected and stroke['ordering']==i and stroke['semanticRole']==0 and stroke['style']==style,'catalog geometry/style')
        require(uuid.UUID(stroke['id']['rawValue'])==stable('stroke:'+seed+':'+str(i)),'catalog stroke ID')
