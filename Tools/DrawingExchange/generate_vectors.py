"""Reproduce additive DX-02 vectors without changing the DX-01 baseline."""
import copy, json, zipfile
from pathlib import Path
from reader import sha256, program_digest
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'Tests/Fixtures/DrawingExchange/dx02'
OUT.mkdir(exist_ok=True); (OUT/'objects').mkdir(exist_ok=True)
for old in (OUT/'objects').iterdir(): old.unlink()
def raw(value): return (json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()
def store(value):
    data=value if isinstance(value,bytes) else raw(value)
    digest=sha256(data); (OUT/'objects'/digest).write_bytes(data); return digest
def asset(data,encoding='adaptiveplotter.fixture/1',media='application/json'):
    return dict(object=store(data),byteLength=len(data),mediaType=media,encoding=encoding)
issuer='550e8400-e29b-41d4-a716-446655440000'
def identity(n): return dict(issuer=issuer,revision=f'00000000-0000-4000-8000-{n:012d}')
def ref(record): return dict(**record['ref'],digest=store(record))
with zipfile.ZipFile(ROOT/'Tests/Fixtures/DrawingExchange/v1/source-free.zip') as z:
    baseline_bytes=next(z.read(n) for n in z.namelist() if n.endswith('drawing.json'));baseline=json.loads(baseline_bytes)
    for n in z.namelist():
        if 'objects/' in n: store(z.read(n))
baseprogram=json.loads((OUT/'objects'/baseline['representation']['object']).read_bytes())
base=copy.deepcopy(baseline);base['ref']=identity(1);base['representation']['nominalPenWidthMillimeters']=0.5
receipt=json.loads((OUT/'objects'/baseline['producer']['record']).read_bytes());receipt['nominalPenWidthMillimeters']=0.5;base['producer']['record']=store(receipt)
vectors=[]
def vector(name, record):
    r=ref(record); p=json.loads((OUT/'objects'/record['representation']['object']).read_bytes())
    vectors.append(dict(name=name,ref=r,programHash=record['representation']['programHash'],points=[[v['x'],v['y']] for s in sorted(p['strokes'],key=lambda x:x['ordering']) for v in s['path']['points']]))
vectors.append(dict(name='frozen-v1-sourcefree',ref=dict(**baseline['ref'],digest=store(baseline_bytes)),programHash=baseline['representation']['programHash'],points=[[5,50],[95,50]]))
vector('source-free',base)
photoasset=asset(bytes([1,2,3,4]),'raw-gray8','application/octet-stream')
photoasset['pixelLayout']=dict(width=2,height=2,pixelFormat='gray',componentType='uint8',bitDepth=8,channelOrder=['gray'],rowStride=2,byteOrder='not-applicable',orientation='up',colorInterpretation='linear-gray')
photos=[]
for n in (10,11):
    p=dict(profile='adaptiveplotter.photo/1',requiredFeatures=[],ref=identity(n),original=photoasset,dimensions=dict(width=2,height=2),acquired=dict(state='unknown',provenance='fixture acquisition'),imported=dict(state='known',time=dict(wallTime='2026-11-06T00:00:00.123456Z'),provenance='fixture import'))
    if n==11: p['acquired']=dict(state='known',time=dict(event=dict(clockID='camera.monotonic',bootSession=issuer,ticks='184467440737095516160000',ticksPerSecond=1000000000)),provenance='fixture event-only acquisition')
    photos.append(ref(p))
prep=dict(id='example.preparation',version='1',record=store(dict(profile='example.preparation/1')))
parameters=asset(raw(dict(degrees=90,rotation='clockwise',pixelCenters='half-integer')))
maskparameters=asset(raw(dict(retainValue=255,fillValue=0,apply='after-rotation')))
identityparameters=asset(raw(dict(operation='identity')))
rotated=[3,1,4,2]
consumed=bytes(value if keep else 0 for value,keep in zip(rotated,[0,255,255,0]))
assert list(consumed)==[0,1,4,0]
# Source center (0.5,0.5) maps to (1.5,0.5), whose rotated value is 1.
assert rotated[1]==1
rasterasset=asset(consumed,'raw-gray8','application/octet-stream');rasterasset['pixelLayout']=photoasset['pixelLayout']
mask=asset(bytes([0,255,255,0]),'raw-gray8','application/octet-stream')
mask['pixelLayout']=photoasset['pixelLayout']
inputrefs=[]
for n,photo in enumerate(photos):
    i=dict(profile='adaptiveplotter.image-input/1',requiredFeatures=[],ref=identity(20+n),photo=photo,pixelBasis=dict(orientation='up',origin='top-left',xAxis='right',yAxis='down',pixelEdges='integer',pixelCenters='half-integer',dimensions=dict(width=2,height=2)),operations=[dict(kind='rotate',parameters=parameters),dict(kind='mask',parameters=maskparameters)],sourceToInput=[0,-1,2,1,0,0,0,0,1],inputToField=[50,0,0,0,-50,100,0,0,1],preparation=prep,raster=rasterasset,mask=dict(state='present',asset=mask))
    inputrefs.append(ref(i))
for n,inputref in enumerate(inputrefs):
    d=copy.deepcopy(base);d['ref']=identity(30+n);d['input']=dict(state='present',ref=inputref);d['producer']=dict(id='example.foreign',version='1',record=store(dict(claim='unverified')));vector('masked-rotated' if n==0 else 'equal-byte-distinct-capture',d)
# Identity preparation references the exact original raster.
i=copy.deepcopy(i);i['ref']=identity(22);i['photo']=photos[0];i['operations']=[dict(kind='identity',parameters=identityparameters)];i['mask']=dict(state='none');i['raster']=photoasset;i['sourceToInput']=[1,0,0,0,1,0,0,0,1]
d=copy.deepcopy(base);d['ref']=identity(32);d['input']=dict(state='present',ref=ref(i));d['producer']=dict(id='example.foreign',version='1',record=store(dict(claim='unverified')));vector('photo',d)
parent=copy.deepcopy(base);parent['ref']=identity(40)
p=copy.deepcopy(baseprogram);p['id']['rawValue']='00000000-0000-4000-8000-000000000040';p['source']=dict(kind='fixture',sourceIdentifier='two-stroke-parent')
s=copy.deepcopy(p['strokes'][0]);s['id']['rawValue']='00000000-0000-4000-8000-000000000041';s['ordering']=1;s['path']['points']=[dict(x=10,y=60),dict(x=90,y=60)];p['strokes'].append(s)
def setprogram(d,p):
    digest=program_digest(p);p['contentHash']['bytes']=list(bytes.fromhex(digest));d['representation']['object']=store(p);d['representation']['programHash']=digest
parent['producer']=dict(id='example.foreign',version='1',record=store(dict(claim='unverified')));setprogram(parent,p)
vector('parent',parent)
child=copy.deepcopy(parent);child['ref']=identity(41);child['parent']=dict(state='present',ref=ref(parent));p=copy.deepcopy(p);p['id']['rawValue']='00000000-0000-4000-8000-000000000042';p['strokes']=p['strokes'][:1];setprogram(child,p);vector('pruned-child',child)
for name,n in [('unknown-producer',50),('unknown-required-feature',51),('historical-unknown-units',52),('unknown-optional',53)]:
    d=copy.deepcopy(base);d['ref']=identity(n)
    if name.startswith('unknown-producer'): d['producer']=parent['producer']
    if name=='unknown-required-feature': d['requiredFeatures']=['example.new-meaning/1']
    if name=='historical-unknown-units': d['representation'].pop('nominalPenWidthMillimeters');d['representation']['historicalUnits']=dict(state='unknown');d['producer']=baseline['producer']
    if name=='unknown-optional': d['futureOptional']=dict(escaped='é',precision=1.25,values=[None,True]);
    vector(name,d)
d=copy.deepcopy(parent);d['ref']=identity(60);p=copy.deepcopy(json.loads((OUT/'objects'/parent['representation']['object']).read_bytes()));p['strokes'].reverse();setprogram(d,p);vector('serialized-stroke-order',d)
d=copy.deepcopy(child);d['ref']=identity(61);d['parent']=dict(state='none');p=copy.deepcopy(json.loads((OUT/'objects'/child['representation']['object']).read_bytes()));p['source']['sourceIdentifier']='Cafe\u0301';p['strokes'][0]['path']['points'][0]['x']=-0.0;setprogram(d,p);vector('nfc-signed-zero',d)
d=copy.deepcopy(base);d['ref']=identity(62);d['createdAt']='2026-11-06T00:00:00.123456Z';vector('fractional-timestamp',d)
arrayasset=asset(bytes(16),'array-float32','application/octet-stream');arrayasset['arrayLayout']=dict(shape=[2,2],dtype='float32',layout='row-major',byteOrder='little',units='field')
(OUT/'vectors.json').write_bytes(raw(dict(profile='adaptiveplotter.dx02-vectors/1',vectors=vectors,photos=photos,assets=[photoasset,rasterasset,mask,arrayasset])))
