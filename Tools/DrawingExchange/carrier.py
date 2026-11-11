"""Closed BagIt carrier verifier. No catalog writes, extraction API, or media cache."""
import argparse
from dataclasses import dataclass, field
import hashlib
import os
from pathlib import Path
import re
import stat
import struct
import tempfile
import unicodedata
import zipfile
import zlib
import reader
import native
import json

class UnsupportedFormat(ValueError):
    """Preservable transport/profile outside this reader's declared capabilities."""

@dataclass(frozen=True)
class Limits:
    entries: int = 100000
    total_bytes: int = 128 * 1024**3
    file_bytes: int = 32 * 1024**3
    record_bytes: int = 8 * 1024**2
    tag_bytes: int = 32 * 1024**2
    expansion_ratio: int = 10000
    chunk_bytes: int = 1024 * 1024
    terminal_record_bytes: int = 256 * 1024**2
    materialized_bytes: int = 256 * 1024**2

BAGIT = b'BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n'
DIGEST = re.compile(r'[0-9a-f]{64}')

def safe_path(name):
    reader.require(type(name) is str and name and len(name.encode('utf8')) <= 4096, 'path length')
    reader.require(not name.startswith('/') and '\\' not in name and ':' not in name and
                   all(unicodedata.category(c)!='Cc' for c in name), 'unsafe path')
    reader.require(all(p not in ('', '.', '..') and len(p.encode('utf8'))<=255 for p in name.split('/')), 'path component')
    reader.require(unicodedata.normalize('NFC', name) == name, 'non-NFC path')
    return name

def fingerprint(s):
    return (s.st_dev, s.st_ino, s.st_mode, s.st_nlink, s.st_size, s.st_mtime_ns, s.st_ctime_ns)

class FileBackedStore:
    def __init__(self, root, inventory, limits):
        self.root, self.inventory, self.limits = Path(root), inventory, limits
        self.objects = {}
        self.materialized_objects=set();self.materialized_bytes=0
        self.root_fingerprint=fingerprint(os.stat(self.root,follow_symlinks=False))
        self.fingerprints = {p:fingerprint(os.stat(self.root/p,follow_symlinks=False)) for p in inventory}
        for path, (digest, size) in inventory.items():
            if path.startswith('data/') and path != 'data/exchange.json':
                self.objects.setdefault(digest, (path, size))
    def object_size(self, digest):
        reader.require(type(digest) is str and DIGEST.fullmatch(digest), 'object digest')
        reader.require(digest in self.objects, 'missing object')
        return self.objects[digest][1]
    def open_object(self, digest):
        self.object_size(digest)
        path, _ = self.objects[digest]
        directory=os.open(self.root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        try:
            reader.require(os.fstat(directory).st_ino==self.root_fingerprint[1] and os.fstat(directory).st_dev==self.root_fingerprint[0],'staging root changed')
            parts=path.split('/')
            for component in parts[:-1]:
                child=os.open(component,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=directory)
                os.close(directory);directory=child
            fd=os.open(parts[-1],os.O_RDONLY|os.O_NOFOLLOW,dir_fd=directory)
        finally:os.close(directory)
        s = os.fstat(fd)
        if not (stat.S_ISREG(s.st_mode) and s.st_nlink == 1 and s.st_size == self.objects[digest][1] and fingerprint(s)==self.fingerprints[path]):
            os.close(fd); raise ValueError('staged object changed')
        return os.fdopen(fd, 'rb')
    def read_object(self, digest, maximum=None):
        size = self.object_size(digest)
        maximum = self.limits.record_bytes if maximum is None else maximum
        reader.require(size <= maximum, 'object size')
        if digest not in self.materialized_objects:
            reader.require(size <= self.limits.materialized_bytes-self.materialized_bytes,'package materialization budget')
            self.materialized_objects.add(digest);self.materialized_bytes+=size
        with self.open_object(digest) as f:
            before=fingerprint(os.fstat(f.fileno()));raw = f.read(maximum+1)
            reader.require(fingerprint(os.fstat(f.fileno()))==before,'staged object changed while reading')
        reader.require(len(raw) == size, 'staged object changed')
        return raw

    def require_path(self, ref, kind):
        suffix={"drawings":"drawing.json","inputs":"input.json","photos":"photo.json"}[kind]
        path=f"data/{kind}/{ref['issuer']}/{ref['revision']}/{suffix}"
        reader.require(path in self.inventory and self.inventory[path][0]==ref['digest'],'typed record path/hash')
    def validate_media(self, descriptor, dimensions=None):
        encoding=descriptor['encoding']; media=descriptor['mediaType']
        if encoding not in ('png','jpeg','jpg'): return False
        reader.require(self.object_size(descriptor['object'])<=64*1024**2,'encoded image bound')
        with self.open_object(descriptor['object']) as stream:
            head=stream.read(32)
            if encoding=='png':
                reader.require(media=='image/png' and descriptor.get('containerType','png') in ('png','image/png'),'PNG type')
                reader.require(head[:8]==b'\x89PNG\r\n\x1a\n' and head[8:16]==b'\x00\x00\x00\rIHDR','PNG header')
                width,height=struct.unpack('>II',head[16:24])
                stream.seek(8); seen_data=False; seen_end=False
                while not seen_end:
                    h=stream.read(8);reader.require(len(h)==8,'PNG truncated chunk')
                    count,kind=struct.unpack('>I4s',h)
                    reader.require(count<=64*1024**2 and stream.tell()+count+4<=self.object_size(descriptor['object']),'PNG chunk range')
                    crc=zlib.crc32(kind);remaining=count
                    while remaining:
                        chunk=stream.read(min(remaining,self.limits.chunk_bytes));reader.require(bool(chunk),'PNG truncated');remaining-=len(chunk);crc=zlib.crc32(chunk,crc)
                    expected=stream.read(4);reader.require(len(expected)==4 and crc==struct.unpack('>I',expected)[0],'PNG CRC')
                    seen_data |= kind==b'IDAT'
                    seen_end=kind==b'IEND'
                    if seen_end:reader.require(count==0 and seen_data and stream.tell()==self.object_size(descriptor['object']),'PNG end/trailing data')
            else:
                reader.require(media=='image/jpeg' and descriptor.get('containerType','jpeg') in ('jpeg','jpg','image/jpeg'),'JPEG type')
                reader.require(head[:2]==b'\xff\xd8','JPEG header'); stream.seek(2)
                width=height=None
                while stream.tell()<self.object_size(descriptor['object']):
                    marker=stream.read(2); reader.require(len(marker)==2 and marker[0]==255,'JPEG marker')
                    while marker[1]==255: marker=b'\xff'+stream.read(1)
                    reader.require(marker[1] not in (0,0xda,0xd9),'JPEG dimensions missing')
                    if marker[1] in (1,*range(0xd0,0xd8)): continue
                    size=stream.read(2);reader.require(len(size)==2,'JPEG length'); n=struct.unpack('>H',size)[0]
                    reader.require(n>=2 and stream.tell()+n-2<=self.object_size(descriptor['object']),'JPEG segment range')
                    if marker[1] in (0xc0,0xc1,0xc2):
                        data=stream.read(6); reader.require(len(data)==6 and n>=8,'JPEG SOF')
                        height,width=struct.unpack('>HH',data[1:5]);break
                    stream.seek(n-2,1)
                reader.require(width is not None,'JPEG dimensions missing')
                stream.seek(-2,2);reader.require(stream.read(2)==b'\xff\xd9','JPEG truncated end')
        reader.require(0<width<=8192 and 0<height<=8192 and width*height<=32*1024**2,'encoded dimensions')
        for expected in (dimensions,descriptor.get('dimensions')):
            if expected is not None: reader.require({k:expected[k] for k in ('width','height')}=={'width':width,'height':height},'encoded dimension mismatch')
        # Header facts alone grant no decoded source semantics.
        return False

@dataclass
class VerifiedCarrier:
    staging: Path
    index: dict
    store: FileBackedStore
    drawings: list
    unsupported: list
    native_inspections: list = field(default_factory=list)

class _Stager:
    def __init__(self, parent, limits, cancelled, fault):
        self.root = Path(tempfile.mkdtemp(prefix='drawing-exchange-', dir=parent))
        os.chmod(self.root, 0o700)
        self.limits, self.cancelled, self.fault = limits, cancelled, fault
        self.inventory, self.names, self.total = {}, set(), 0
        self.directories=set(); self.spellings={}
    def check(self):
        if self.cancelled and self.cancelled(): raise InterruptedError('import cancelled; staging retained: '+str(self.root))
    def register_spelling(self,name):
        parts=name.split('/')
        for n in range(1,len(parts)+1):
            prefix='/'.join(parts[:n]);key=prefix.casefold()
            reader.require(key not in self.spellings or self.spellings[key]==prefix,'component case collision')
            self.spellings[key]=prefix
    def write(self, name, chunks, expected=None):
        safe_path(name); self.register_spelling(name); key=name.casefold()
        reader.require(key not in self.names and len(self.names) < self.limits.entries, 'duplicate/colliding path or entry limit')
        reader.require(key not in self.directories,'file/directory collision')
        for parent in Path(name).parents:
            if str(parent)=='.': continue
            parent_key=str(parent).casefold();reader.require(parent_key not in self.names,'file as parent')
            self.directories.add(parent_key)
        self.names.add(key)
        path=self.root/name; path.parent.mkdir(parents=True, exist_ok=True)
        digest=hashlib.sha256(); size=0
        with path.open('xb') as out:
            for chunk in chunks:
                self.check(); size += len(chunk); self.total += len(chunk)
                reader.require(size <= self.limits.file_bytes and self.total <= self.limits.total_bytes, 'carrier byte limit')
                out.write(chunk); digest.update(chunk)
                if self.fault: self.fault(name, size)
        reader.require(expected is None or size == expected, 'entry length')
        self.inventory[name]=(digest.hexdigest(), size)
    def directory(self, source):
        flags=os.O_RDONLY | os.O_NOFOLLOW | os.O_DIRECTORY
        fd=os.open(source, flags)
        def walk(directory, prefix=''):
            before=fingerprint(os.fstat(directory))
            for name in sorted(os.listdir(directory)):
                self.check(); rel=safe_path(prefix+name)
                s=os.stat(name, dir_fd=directory, follow_symlinks=False)
                if stat.S_ISDIR(s.st_mode):
                    self.register_spelling(rel)
                    key=rel.casefold(); reader.require(key not in self.names and key not in self.directories,'directory collision')
                    self.directories.add(key)
                    child=os.open(name, flags, dir_fd=directory)
                    try:
                        reader.require(fingerprint(os.fstat(child)) == fingerprint(s), 'directory raced')
                        walk(child, rel+'/')
                    finally: os.close(child)
                else:
                    reader.require(stat.S_ISREG(s.st_mode) and s.st_nlink == 1, 'link/special entry')
                    f=os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
                    with os.fdopen(f,'rb') as stream:
                        reader.require(fingerprint(os.fstat(f)) == fingerprint(s), 'file raced')
                        self.write(rel, iter(lambda:stream.read(self.limits.chunk_bytes), b''), s.st_size)
                        reader.require(fingerprint(os.fstat(f)) == fingerprint(s), 'file changed')
            reader.require(fingerprint(os.fstat(directory)) == before, 'directory changed')
        try: walk(fd)
        finally: os.close(fd)
    def archive(self, source):
        # Keep the exact incoming archive even on cancellation/validation failure.
        original=os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(original,'rb') as f:
            before=fingerprint(os.fstat(original)); reader.require(stat.S_ISREG(os.fstat(original).st_mode), 'archive file type')
            with (self.root/'incoming.zip').open('xb') as out:
                while True:
                    chunk=f.read(self.limits.chunk_bytes)
                    if not chunk: break
                    reader.require(out.tell()+len(chunk) <= self.limits.total_bytes, 'archive byte limit')
                    out.write(chunk)
            reader.require(fingerprint(os.fstat(original)) == before, 'archive changed')
        with (self.root/'incoming.zip').open('rb') as raw:
            raw.seek(0,2); length=raw.tell(); reader.require(length>=22,'truncated ZIP')
            raw.seek(max(0,length-65557)); tail=raw.read(); position=tail.rfind(b'PK\x05\x06')
            reader.require(position>=0 and position+22<=len(tail),'missing EOCD')
            end=tail[position:position+22]; eocd=length-len(tail)+position
            _,disk,central_disk,n_disk,n,size,offset,comment=struct.unpack('<4s4H2IH',end)
            if disk or central_disk or n_disk!=n or n==65535 or size==0xffffffff or offset==0xffffffff:
                raise UnsupportedFormat('single-disk classic ZIP required; ZIP64 unsupported')
            reader.require(eocd+22+comment==length and offset+size==eocd and n<=self.limits.entries and size<=self.limits.tag_bytes,'ZIP central range')
            with zipfile.ZipFile(raw) as archive:
                entries=archive.infolist(); reader.require(len(entries)==n,'ZIP central count')
                central_cursor=offset;central_times=[]
                for item in entries:
                    raw.seek(central_cursor); h=raw.read(46);reader.require(len(h)==46 and h[:4]==b'PK\x01\x02','central header')
                    central_times.append(struct.unpack_from('<HH',h,12))
                    nl,xl,cl,disk_start=struct.unpack_from('<HHHH',h,28);reader.require(disk_start==0,'ZIP central disk')
                    central_cursor+=46+nl+xl+cl
                    reader.require(central_cursor<=offset+size,'central range')
                reader.require(central_cursor==offset+size,'central trailing junk')
                cursor=0
                for info,central_time in zip(entries,central_times):
                    self.check()
                    reader.require(info.header_offset==cursor,'ZIP local gap/overlap/order')
                    if info.flag_bits & ~0x800 or info.compress_type not in (0,8):
                        raise UnsupportedFormat('ZIP supports stored/deflate, optional UTF8 flag; no encryption/descriptors')
                    if info.extract_version>20: raise UnsupportedFormat('ZIP version unsupported')
                    mode=(info.external_attr>>16)&0xffff; kind=stat.S_IFMT(mode)
                    reader.require(kind in (0,stat.S_IFREG,stat.S_IFDIR) and (info.is_dir() or not info.external_attr&0x10), 'ZIP link/special/directory')
                    self._extra(info.extra)
                    raw.seek(cursor); header=raw.read(30); reader.require(len(header)==30,'ZIP local header')
                    sig,version,flags,method,tm,dt,crc,compressed,uncompressed,nlen,xlen=struct.unpack('<4s5H3I2H',header)
                    reader.require(sig==b'PK\x03\x04' and version==info.extract_version and version<=20 and flags==info.flag_bits and method==info.compress_type and
                                   crc==info.CRC and compressed==info.compress_size and uncompressed==info.file_size and
                                   (tm,dt)==central_time,'ZIP local/central mismatch')
                    name=raw.read(nlen); extra=raw.read(xlen); self._extra(extra)
                    reader.require(len(extra)==xlen,'ZIP extra truncation')
                    decoded=name.decode('utf8' if flags&0x800 else 'cp437')
                    reader.require(decoded==info.filename and '\x00' not in decoded,'ZIP filename mismatch')
                    start=cursor+30+nlen+xlen; finish=start+compressed
                    reader.require(finish<=offset and uncompressed<=self.limits.file_bytes and
                                   uncompressed<=max(1,compressed)*self.limits.expansion_ratio,'ZIP expansion/range')
                    raw.seek(start)
                    def chunks():
                        remaining=compressed; dec=zlib.decompressobj(-15) if method==8 else None
                        actual=0; checksum=0
                        while remaining:
                            data=raw.read(min(remaining,self.limits.chunk_bytes)); reader.require(bool(data),'ZIP truncated data'); remaining-=len(data)
                            if dec:
                                pending=data
                                while pending:
                                    out=dec.decompress(pending,self.limits.chunk_bytes); pending=dec.unconsumed_tail
                                    actual+=len(out); reader.require(actual<=uncompressed,'ZIP expansion beyond declaration')
                                    checksum=zlib.crc32(out,checksum); yield out
                                reader.require(not dec.unused_data,'ZIP trailing compressed junk')
                            else:
                                actual+=len(data); checksum=zlib.crc32(data,checksum); yield data
                        reader.require(not dec or (dec.eof and not dec.unused_data and not dec.unconsumed_tail),'ZIP incomplete deflate')
                        reader.require(actual==uncompressed and checksum==crc,'ZIP size/CRC')
                    if info.is_dir():
                        name=safe_path(decoded[:-1]); self.register_spelling(name); key=name.casefold()
                        reader.require(uncompressed==0 and key not in self.names and key not in self.directories,'ZIP directory entry')
                        for block in chunks():reader.require(not block,'ZIP directory content')
                        self.directories.add(key); (self.root/name).mkdir(parents=True,exist_ok=True)
                    else:
                        reader.require(kind!=stat.S_IFDIR,'ZIP directory type mismatch')
                        self.write(decoded,chunks(),uncompressed)
                    cursor=finish
                reader.require(cursor==offset,'ZIP unlisted local bytes')
    @staticmethod
    def _extra(extra):
        cursor=0
        while cursor<len(extra):
            reader.require(cursor+4<=len(extra),'ZIP extra header')
            kind,length=struct.unpack_from('<HH',extra,cursor);cursor+=4
            reader.require(cursor+length<=len(extra),'ZIP extra length')
            if kind==1: raise UnsupportedFormat('ZIP64 unsupported')
            # Unix link, Unicode override and arbitrary extension interpretation is outside profile.
            if kind not in (0x5455,0x7875): raise UnsupportedFormat('unsupported ZIP extra field')
            cursor+=length

def _manifest(stage, name):
    reader.require(name in stage.inventory and stage.inventory[name][1]<=stage.limits.tag_bytes,'missing/oversized manifest')
    raw=(stage.root/name).read_bytes(); reader.require(raw.endswith(b'\n') and b'\r' not in raw and not raw.startswith(b'\xef\xbb\xbf'),'manifest encoding')
    result={}
    for line in raw.decode('utf8').split('\n')[:-1]:
        reader.require(re.fullmatch(r'[0-9a-f]{64}  .+',line) is not None,'manifest line')
        digest,path=line[:64],safe_path(line[66:]); reader.require(path not in result,'duplicate manifest entry');result[path]=digest
    return result

def import_carrier(source, staging_parent, *, limits=Limits(), cancelled=None, fault=None):
    """Verify into private retained staging; failures expose ``error.staging``."""
    stage=_Stager(staging_parent,limits,cancelled,fault)
    try:
        source=Path(source)
        if source.is_dir() and not source.is_symlink(): stage.directory(source)
        else: stage.archive(source)
        inv=stage.inventory
        reader.require('fetch.txt' not in inv and 'bagit.txt' in inv and inv['bagit.txt'][1]==len(BAGIT) and (stage.root/'bagit.txt').read_bytes()==BAGIT,'BagIt profile')
        payload=_manifest(stage,'manifest-sha256.txt'); tags=_manifest(stage,'tagmanifest-sha256.txt')
        reader.require(set(payload)=={p for p in inv if p.startswith('data/')},'payload manifest closure')
        reader.require(set(tags)==set(inv)-set(payload)-{'tagmanifest-sha256.txt'} and
                       {'bagit.txt','manifest-sha256.txt'}<=tags.keys(),'tag manifest closure')
        for path,digest in {**payload,**tags}.items(): reader.require(inv[path][0]==digest,'manifest digest mismatch')
        reader.require(inv['data/exchange.json'][1]<=limits.record_bytes,'index bound')
        index=reader.parse((stage.root/'data/exchange.json').read_bytes(),limits.record_bytes)
        store=FileBackedStore(stage.root,inv,limits)
        fields(index,('profile',));text(index['profile'])
        unsupported=[]
        if index.get('profile')!='adaptiveplotter.exchange/1':
            return VerifiedCarrier(stage.root,index,store,[],['unsupported exchange profile'])
        envelope_shape('index',index,unsupported)
        reader.walltime(index['includedAsOf']); unsupported.extend(reader.features({**index,'requiredFeatures':index.get('requiredFeatures',[])},()))
        exchange_blocked=bool(unsupported)
        descriptors={}
        for d in index['assets']:
            digest=d['object']
            reader.require(digest not in descriptors or reader.asset_facts(descriptors[digest])==reader.asset_facts(d),'contradictory duplicate asset descriptor')
            reader.require(store.object_size(digest)==d['byteLength'],'descriptor length')
            expected='data/objects/sha256/'+digest
            reader.require(expected in inv and inv[expected][0]==digest,'asset path/hash')
            reader.asset(store,d); descriptors[digest]=d
        for path,(digest,size) in inv.items():
            if path.startswith('data/objects/sha256/'):
                reader.require(path=='data/objects/sha256/'+digest and digest in descriptors,'unlisted/misnamed object')
        drawing_results={}
        for ref in index['roots']:
            identity=tuple(ref[k] for k in ('issuer','revision','digest'))
            if identity not in drawing_results:drawing_results[identity]=reader.drawing(store,ref,asset_descriptors=descriptors)
        drawings=list(drawing_results.values())
        # Closure validator covers all indexed records, including opaque evidence.
        native_inspections = validate_closure(store,index,descriptors,unsupported)
        if exchange_blocked:
            for result in drawings:
                result["blocked"]=True
                result["capabilities"]={k:False for k in ("preview","plot","edit","regenerate","train")}
        return VerifiedCarrier(stage.root,index,store,drawings,unsupported,native_inspections)
    except (zlib.error,UnicodeError,struct.error,KeyError,TypeError,AttributeError) as cause:
        error=ValueError('invalid carrier byte encoding/compression')
        error.staging=stage.root
        raise error from cause
    except Exception as error:
        error.staging=stage.root
        raise

# These are explicit owning-envelope checks, not a general schema interpreter.
def fields(value,required):
    reader.require(type(value) is dict and set(required)<=value.keys(),'required object fields')
    return value

def text(value):
    reader.require(type(value) is str and bool(value),'required nonempty string')
    return value

def namespaced(value):
    text(value);reader.require(re.fullmatch(r'[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+(?:[/:][A-Za-z0-9._/-]+)?',value) is not None,'namespaced ID')

def hash_text(value):
    reader.require(type(value) is str and DIGEST.fullmatch(value) is not None,'SHA256 scalar')

def array(value,minimum=0):
    reader.require(type(value) is list and len(value)>=minimum,'required array')
    return value

def question(value):
    fields(value,('id','version','text'));namespaced(value['id']);text(value['version']);text(value['text'])

def reviewer(value,unsupported):
    fields(value,('kind','id'));text(value['kind']);text(value['id'])
    if 'version' in value:text(value['version'])
    if value['kind']=='algorithm':text(value['version'])
    elif value['kind']!='human':unsupported.append('unsupported reviewer kind')

def producer(value):
    fields(value,('id','version','record'));namespaced(value['id']);text(value['version']);hash_text(value['record'])

def envelope_shape(kind,value,unsupported):
    if kind=='index':
        fields(value,('profile','kind','roots','includedAsOf','assets','attempts','assessments'));text(value['kind'])
        for name in ('roots','assets','attempts','assessments','photos','inputs','jobs','rankingCapsules'):
            if name in value:array(value[name])
        if value['kind'] in ('drawing','result'):array(value['roots'],1)
        if value['kind']=='result':array(value['jobs'],1)
        elif value['kind'] not in ('drawing','feedback'):unsupported.append('unsupported exchange kind')
        reader.walltime(value['includedAsOf'])
        return
    required={
        'job':('handle','client','drawing','preparedPlan','requestedMediumOptions','issuedAt','disposition','reason'),
        'attempt':('issuerArchive','run','sequence','previous','sealed','drawing','job','environment','intent','coverage','state','dispatch','observation','terminalRecord','assessments'),
        'assessment':('ref','targets','reviewer','time','question','answer','supportingAssets'),
        'ranking-capsule':('ref','geometry','createdAt','presentations','question','reviewer','response','limitations'),
        'coverage':('includedAsOf','entries','frontiers'),
    }
    if kind not in required:return
    fields(value,('profile','requiredFeatures',*required[kind]))
    if kind=='job':
        fields(value['handle'],('engine','job'));fields(value['client'],('namespace','request','requestDigest'))
        text(value['reason']);text(value['disposition']);reader.timestamp(value['issuedAt'])
        if 'issuance' in value:reader.uuid_text(value['issuance'])
    elif kind=='attempt':
        reader.uuid_text(value['issuerArchive']);reader.uuid_text(value['run']);reader.integer(value['sequence'],1)
        reader.require(type(value['sealed']) is bool,'sealed scalar')
        if value['previous'] is not None:hash_text(value['previous'])
        for name in ('environment','state','dispatch','observation'):text(value[name])
        hash_text(value['intent']);hash_text(value['coverage'])
        if value['terminalRecord'] is not None:hash_text(value['terminalRecord'])
        array(value['assessments'])
        for sync in array(value.get('clockSynchronizations',[])):
            fields(sync,('fromClock','fromBootSession','toClock','toBootSession','fromTicks','toTicks','errorBoundSeconds'))
            for name in ('fromClock','toClock'):text(sync[name])
            for name in ('fromBootSession','toBootSession'):reader.uuid_text(sync[name])
            for name in ('fromTicks','toTicks'):
                reader.require(type(sync[name]) is str and re.fullmatch(r'0|[1-9][0-9]*',sync[name]) is not None,'clock ticks')
            reader.require(reader.number(sync['errorBoundSeconds'])>=0,'clock error bound')
    elif kind in ('assessment','ranking-capsule'):
        reviewer(value['reviewer'],unsupported);question(value['question'])
        if kind=='assessment':
            array(value['targets'],1);array(value['supportingAssets']);array(value.get('supersedes',[]))
            fields(value['answer'],('type','value'));namespaced(value['answer']['type']);reader.timestamp(value['time'])
            for target in value['targets']:fields(target,('kind',));text(target['kind'])
        else:
            reader.require(value['geometry']=='omitted' and type(value['geometry']) is str,'ranking geometry')
            reader.require(value['limitations']=='Features only; no geometry re-extraction or arbitrary future image labels.','ranking limitations')
            reader.timestamp(value['createdAt']);array(value['presentations'],2)
            for p in value['presentations']:
                fields(p,('id','features','producer','extractor'));producer(p['producer']);producer(p['extractor'])
            fields(value['response'],('kind',));text(value['response']['kind'])
    elif kind=='coverage':
        reader.timestamp(value['includedAsOf']);array(value['entries'])
        fields(value['frontiers'],('planned','commanded','controllerCompleted','inkVerified'))

def validate_closure(store,index,descriptors,unsupported):
    """Independent envelope/link admission; native evidence remains unsupported."""
    envelope_shape('index',index,unsupported)
    identities={}; visited=set(); jobs={}; requests={}; attempts={}; used=set();admitted_paths=set();validated_drawings=set();native_inspections=[]
    profiles={'drawing':'drawing','photo':'photo','input':'image-input','assessment':'assessment',
              'ranking-capsule':'feature-ranking','attempt':'plot-attempt','job':'plot-job-receipt'}
    def key(ref): return tuple(ref[k] for k in ('issuer','revision','digest'))
    root_keys={key(r) for r in index['roots']}
    def asset(d):
        reader.require(isinstance(d,dict) and d['object'] in descriptors,'undeclared asset')
        base=descriptors[d['object']]
        reader.require(all(k not in reader.asset_facts(d) or reader.asset_facts(d)[k]==v for k,v in reader.asset_facts(base).items()),'asset descriptor disagreement')
        reader.asset(store,d,descriptors); used.add(d['object'])
    def digest(d):
        reader.require(d in descriptors,'undeclared payload digest'); asset(descriptors[d])
        maximum=min(store.limits.terminal_record_bytes,native.TERMINAL_JSON_BYTES) if descriptors[d]['encoding']==native.TERMINAL else store.limits.record_bytes
        return reader.parse(store.read_object(d,maximum),maximum) if descriptors[d]['mediaType']=='application/json' else None
    def typed(ref,kind):
        if kind=='attempt':
            reader.require(set(ref)=={'archive','run','sequence','digest'},'attempt reference fields')
            reader.uuid_text(ref['archive']);reader.uuid_text(ref['run']);reader.integer(ref['sequence'],1)
            identity=('attempt',ref['archive'],ref['run'],ref['sequence'])
            path=f"data/attempts/{ref['archive']}/{ref['run']}/{ref['sequence']}/attempt.json"
        elif kind=='job':
            reader.require(set(ref)=={'engine','job','receiptDigest'},'job reference fields')
            reader.uuid_text(ref['engine']);reader.uuid_text(ref['job'])
            identity=('job',ref['engine'],ref['job']);path=f"data/jobs/{ref['engine']}/{ref['job']}/receipt.json"
        else:
            reader.require(set(ref)=={'issuer','revision','digest'},'typed reference fields')
            reader.uuid_text(ref['issuer']);reader.uuid_text(ref['revision'])
            identity=('record',ref['issuer'],ref['revision'])
            paths={'drawing':f"data/drawings/{ref['issuer']}/{ref['revision']}/drawing.json",
                   'photo':f"data/photos/{ref['issuer']}/{ref['revision']}/photo.json",
                   'input':f"data/inputs/{ref['issuer']}/{ref['revision']}/input.json",
                   'assessment':f"data/assessments/{ref['issuer']}/{ref['revision']}.json",
                   'ranking-capsule':f"data/rankings/{ref['issuer']}/{ref['revision']}.json"}
            path=paths[kind]
        d=ref.get('digest',ref.get('receiptDigest'));reader.require(type(d) is str and DIGEST.fullmatch(d),'reference digest')
        reader.require(path in store.inventory and store.inventory[path][0]==d,'missing/wrong typed path or digest')
        reader.require(identity not in identities or identities[identity]==(kind,d),'identity/type divergence')
        identities[identity]=(kind,d);used.add(d);admitted_paths.add(path)
        value=reader.parse(store.read_object(d,store.limits.record_bytes))
        fields(value,('profile',));text(value['profile'])
        if (kind,d) in visited: return value
        visited.add((kind,d))
        expected='adaptiveplotter.'+profiles[kind]+'/1'
        reader.require(not reader.known_wrong_profile(value.get('profile'),profiles[kind]),'known wrong record type')
        if value.get('profile')!=expected:
            if kind=='job':jobs[(ref['engine'],ref['job'],d)]=value
            elif kind=='attempt':attempts[(ref['archive'],ref['run'],ref['sequence'])]=(d,value)
            unsupported.append('unsupported '+kind+' profile');return value
        envelope_shape(kind,value,unsupported)
        unsupported.extend(reader.features(value,()))
        if kind not in ('job','attempt'): reader.require(value['ref']=={k:ref[k] for k in ('issuer','revision')},'record identity')
        if kind=='drawing':
            if d not in validated_drawings:
                reader.drawing(store,ref,asset_descriptors=descriptors);validated_drawings.add(d)
            digest(value['representation']['object']); digest(value['producer']['record'])
            for name,child_kind in (('parent','drawing'),('input','input')):
                link=value[name];state=reader.declaration(link)
                if state=='present': typed(link['ref'],child_kind)
        elif kind=='photo':
            asset(value['original'])
            if 'captureFacts' in value: asset(value['captureFacts'])
        elif kind=='input':
            typed(value['photo'],'photo');asset(value['raster']);digest(value['preparation']['record'])
            if value['mask']['state']=='present': asset(value['mask']['asset'])
            for operation in value['operations']:asset(operation['parameters'])
        elif kind=='job':
            reader.require(value['handle']=={k:ref[k] for k in ('engine','job')},'job handle')
            reader.require(key(value['drawing']) in root_keys,'job drawing absent from roots');typed(value['drawing'],'drawing')
            reader.timestamp(value['issuedAt']);asset(value['preparedPlan']);asset(value['requestedMediumOptions'])
            c=value['client'];reader.uuid_text(c['namespace']);reader.uuid_text(c['request'])
            reader.require(DIGEST.fullmatch(c['requestDigest']) is not None,'request digest')
            request=(c['namespace'],c['request']);binding=(c['requestDigest'],identity,d)
            reader.require(request not in requests or requests[request]==binding,'request reuse conflict');requests[request]=binding
            disposition=value['disposition']
            if disposition=='accepted':reader.uuid_text(value['issuance'])
            elif disposition=='refused':reader.require('issuance' not in value,'refused issuance')
            else:unsupported.append('unsupported job disposition')
            jobs[(ref['engine'],ref['job'],d)]=value
        elif kind=='attempt':
            reader.require((value['issuerArchive'],value['run'],value['sequence'])==(ref['archive'],ref['run'],ref['sequence']),'snapshot identity')
            reader.require(type(value['sealed']) is bool,'seal type')
            reader.require(key(value['drawing']) in root_keys,'attempt drawing absent from roots')
            typed(value['drawing'],'drawing');receipt=typed(value['job'],'job')
            if receipt['profile']=='adaptiveplotter.plot-job-receipt/1':
                reader.require(value['drawing']==receipt['drawing'],'attempt receipt drawing')
                reader.require(receipt['disposition']!='refused','refused job attempt')
                if receipt['disposition']=='accepted' and 'issuance' in value:
                    reader.require(value['issuance']==receipt['issuance'],'attempt issuance')
            for field,known in (('environment',('live','simulation')),('dispatch',('not-dispatched','possibleInk')),
                                ('state',('staged','running','cancelling','interrupted','completed','failed','cancelled')),
                                ('observation',('accepted','rejected','unavailable'))):
                if value[field] not in known:unsupported.append('unsupported attempt '+field)
            digest(value['intent']);coverage=digest(value['coverage'])
            if coverage is not None: validate_coverage(coverage,asset,unsupported,lambda ref:typed(ref,'assessment'))
            if value['terminalRecord'] is not None:digest(value['terminalRecord'])
            if 'plan' in value:asset(value['plan'])
            for a in value['assessments']:typed(a,'assessment')
            attempts[(ref['archive'],ref['run'],ref['sequence'])]=(d,value)
            inspection = native.inspect_attempt(store, value, receipt, descriptors, coverage)
            if inspection is None:
                unsupported.append('native intent/coverage/frontier semantics unsupported')
            else:
                native_inspections.append(inspection)
                unsupported.extend(inspection['limitations'])
        elif kind=='assessment':
            reader.timestamp(value['time'])
            reader.require(bool(value['targets']),'assessment targets')
            for target in value['targets']:
                if target['kind']=='asset':
                    reader.require(set(target)=={'kind','asset'},'asset target fields');asset(target['asset'])
                elif target['kind'] in ('drawing','attempt','ranking-capsule'):
                    reader.require(set(target)=={'kind','ref'},'reference target fields');typed(target['ref'],target['kind'])
                else:unsupported.append('unsupported assessment target')
            for d in value['supportingAssets']:asset(d)
            for ref in value.get('supersedes',[]):typed(ref,'assessment')
            if 'regionOrStrokes' in value:asset(value['regionOrStrokes'])
            if 'schema' in value['answer']:asset(value['answer']['schema'])
            unsupported.append('assessment answer semantics unsupported')
        elif kind=='ranking-capsule':
            ids=[]
            for presentation in value['presentations']:
                reader.uuid_text(presentation['id']);ids.append(presentation['id']);asset(presentation['features'])
                for p in ('producer','extractor'):digest(presentation[p]['record'])
            reader.require(len(ids)>=2 and len(set(ids))==len(ids),'ranking presentations')
            response=value['response']
            if response['kind']=='ranking':
                groups=array(response['groups'],1)
                for group in groups:
                    for i in array(group,1):reader.uuid_text(i)
                flat=[i for group in groups for i in group]
                reader.require(groups and all(groups) and len(flat)==len(set(flat)) and set(flat)==set(ids),'ranking groups')
            elif response['kind']=='skip':text(response['reason'])
            else:unsupported.append('unsupported ranking response')
        return value
    for name,kind in (('roots','drawing'),('photos','photo'),('inputs','input'),('jobs','job'),('attempts','attempt'),('assessments','assessment'),('rankingCapsules','ranking-capsule')):
        refs=index.get(name,[]);reader.require(isinstance(refs,list),'index reference array')
        for ref in refs:typed(ref,kind)
    # Closed payloads may include valid retained records that are not selected
    # roots (for example geometry alongside a features-only feedback capsule).
    # Admit those through their exact canonical typed path; do not treat every
    # arbitrary payload file or a coincident digest as an admitted record.
    uuid_pattern=r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'
    record_patterns=[
        (r'data/drawings/'+uuid_pattern+'/'+uuid_pattern+r'/drawing\.json','drawing'),
        (r'data/photos/'+uuid_pattern+'/'+uuid_pattern+r'/photo\.json','photo'),
        (r'data/inputs/'+uuid_pattern+'/'+uuid_pattern+r'/input\.json','input'),
        (r'data/assessments/'+uuid_pattern+'/'+uuid_pattern+r'\.json','assessment'),
        (r'data/rankings/'+uuid_pattern+'/'+uuid_pattern+r'\.json','ranking-capsule'),
        (r'data/jobs/'+uuid_pattern+'/'+uuid_pattern+r'/receipt\.json','job'),
        (r'data/attempts/'+uuid_pattern+'/'+uuid_pattern+r'/([1-9][0-9]*)/attempt\.json','attempt'),
    ]
    for path,(d,size) in store.inventory.items():
        if path=='data/exchange.json' or not path.startswith('data/') or path.startswith('data/objects/sha256/'):continue
        for pattern,kind in record_patterns:
            match=re.fullmatch(pattern,path)
            if match is None:continue
            a,b,*sequence=match.groups()
            if kind=='job':ref={'engine':a,'job':b,'receiptDigest':d}
            elif kind=='attempt':ref={'archive':a,'run':b,'sequence':int(sequence[0]),'digest':d}
            else:ref={'issuer':a,'revision':b,'digest':d}
            typed(ref,kind);break
        reader.require(path in admitted_paths,'unreferenced/noncanonical typed record')
    pending=list(attempts)
    while pending:
        archive,run,sequence=pending.pop();d,value=attempts[(archive,run,sequence)]
        if value['profile']!='adaptiveplotter.plot-attempt/1':continue
        if sequence>1 and (archive,run,sequence-1) not in attempts:
            typed({'archive':archive,'run':run,'sequence':sequence-1,'digest':value['previous']},'attempt')
            pending.append((archive,run,sequence-1))
    if 'scope' in index:asset(index['scope'])
    if index['kind']=='result':reader.require(bool(index.get('jobs')),'result requires job roots')
    run_jobs={};issuance_runs={};possible_ink_runs=set()
    for (archive,run,sequence),(d,value) in sorted(attempts.items()):
        if value['profile']!='adaptiveplotter.plot-attempt/1':continue
        job=value['job'];job_key=(job['engine'],job['job'],job['receiptDigest'])
        reader.require(job_key in jobs and job in index.get('jobs',[]),'attempt job root missing')
        receipt=jobs[job_key]
        known_receipt=receipt['profile']=='adaptiveplotter.plot-job-receipt/1'
        if known_receipt:reader.require(receipt['disposition']!='refused','refused job attempt')
        if sequence==1:reader.require(value['previous'] is None,'first predecessor')
        else:
            predecessor=attempts.get((archive,run,sequence-1));reader.require(predecessor is not None,'incomplete snapshot chain')
            pd,pv=predecessor
            reader.require(value['previous']==pd,'predecessor digest')
            if pv['profile']=='adaptiveplotter.plot-attempt/1':
                reader.require(not pv['sealed'],'post-seal continuation')
                reader.require(all(value[k]==pv[k] for k in ('drawing','job','environment','intent')),'snapshot binding divergence')
        run_key=(archive,run)
        reader.require(run_key not in possible_ink_runs or value['dispatch']!='not-dispatched','possibleInk reverted')
        if value['dispatch']=='possibleInk':possible_ink_runs.add(run_key)
        # Unknown disposition remains opaque; acceptance/issuance semantics cannot
        # be inferred. Exact receipt links and the known snapshot chain still hold.
        if not known_receipt or receipt['disposition']!='accepted':continue
        binding=(archive,run)
        reader.require(job_key not in run_jobs or run_jobs[job_key]==binding,'multiple runs per job');run_jobs[job_key]=binding
        issuance=(job['engine'],receipt['issuance'])
        reader.require(issuance not in issuance_runs or issuance_runs[issuance]==binding,'multiple runs per issuance');issuance_runs[issuance]=binding
    if index['kind']=='result':
        for job_key,receipt in jobs.items():
            if receipt['profile']=='adaptiveplotter.plot-job-receipt/1' and receipt['disposition']=='accepted':
                if job_key not in run_jobs and any(v['profile']!='adaptiveplotter.plot-attempt/1' for d,v in attempts.values()):
                    unsupported.append('opaque attempt prevents complete job chain validation')
                else:reader.require(job_key in run_jobs,'accepted result requires an attempt chain')
    # Every record in a known carrier path must be admitted by a typed relationship.
    for path,(d,size) in store.inventory.items():
        if path.startswith('data/') and path!='data/exchange.json' and not path.startswith('data/objects/sha256/'):
            reader.require(path in admitted_paths,'unreferenced typed record')
    prior_native={}
    for row in sorted(native_inspections, key=lambda r:(r['archive'],r['run'],r['sequence'])):
        key=(row['archive'],row['run']);prior=prior_native.get(key)
        row['predecessorProofSupported']=(row['sequence']==1 or (prior is not None and prior['sequence']==row['sequence']-1 and
            prior['selectedRequirementsSupported'] and prior['predecessorProofSupported'] and prior['nativeBindingVerified']))
        if not row['predecessorProofSupported']:
            row['selectedRequirementsSupported']=False
            row['limitations'].append('Exact predecessor owner proof or required semantics are unavailable.')
        if prior is not None:
            native.require_extension(store,prior,row)
            for name,value in prior['frontiers'].items():
                if name in row['frontiers']:reader.require(row['frontiers'][name]>=value,'native cumulative frontier reverted')
            reader.require(set(prior['originalMedia'])<=set(row['originalMedia']),'native cumulative media reverted')
        prior_native[key]=row
    unsupported[:]=sorted(set(unsupported))
    return sorted(native_inspections, key=lambda row: (row['archive'], row['run'], row['sequence']))

def validate_coverage(value,asset,unsupported,assessment):
    fields(value,('profile',));text(value['profile'])
    if value.get('profile')!='adaptiveplotter.coverage/1':
        reader.require(not reader.known_wrong_profile(value.get('profile'),'coverage'),'wrong coverage type')
        unsupported.append('unsupported coverage profile');return
    envelope_shape('coverage',value,unsupported)
    unsupported.extend(reader.features(value,()));reader.timestamp(value['includedAsOf'])
    for field in ('planned','commanded','controllerCompleted','inkVerified'):reader.require(field in value['frontiers'],'missing frontier')
    for evidence in [*value['entries'],*(value['frontiers'][name] for name in ('planned','commanded','controllerCompleted','inkVerified'))]:
        fields(evidence,('kind','status'));namespaced(evidence['kind']);status=text(evidence['status'])
        if 'registration' in evidence:asset(evidence['registration'])
        if 'captureTime' in evidence:reader.timestamp(evidence['captureTime'])
        if 'assessment' in evidence:assessment(evidence['assessment'])
        if 'source' in evidence:text(evidence['source'])
        if 'reason' in evidence:text(evidence['reason'])
        if status=='present':asset(evidence['asset'])
        elif status in ('never-captured','unavailable','intentionally-withheld'):
            reader.require(type(evidence.get('reason')) is str and bool(evidence['reason']) and 'asset' not in evidence,'evidence unavailable declaration')
        else:
            if 'asset' in evidence:asset(evidence['asset'])
            unsupported.append('unsupported evidence status')


def inspect_result(result):
    """Inspection is available without a model, controller, camera or Library."""
    index=result.index
    return {'profile': 'adaptiveplotter.offline-result-inspection/1', 'staging': str(result.staging),
            'integrityVerified': True, 'includedAsOf': index.get('includedAsOf'),
            'drawings': index.get('roots', []), 'jobs': index.get('jobs', []),
            'snapshots': index.get('attempts', []), 'nativeBindings': result.native_inspections,
            'unsupported': result.unsupported, 'readinessAuthority': False, 'retryAuthority': False,
            'physicalValidityClaim': False, 'task': inspect_task(result)}


TASK_CONTRACTS = {
    'adaptiveplotter.result-inspection/1': (
        'Exact Drawing/job/snapshot/assessment closure; unavailable facts remain explicit.',
        'Inspection only; no positive or negative training label.'),
    'adaptiveplotter.interruption-state/1': (
        'Exact native pre-motion binding and recorded stage/frontier; no elapsed-clock inference.',
        'Recorded interruption category and frontier only; no inferred ink or image residual.'),
    'adaptiveplotter.aligned-residual/1': (
        'Exact live target, attributable aligned observation, registration and measured residual label.',
        'A registered aligned-residual measurement; testimony, preference and synthetic images are not labels.')}


def task_grouping_keys(result, drawing):
    keys=set();seen=set()
    def visit(ref, depth=0):
        reader.require(depth<=64 and len(seen)<=10000,'task grouping bound')
        key=(ref['issuer'],ref['revision'],ref['digest'])
        if key in seen:return
        seen.add(key);keys.add('drawing:'+ref['issuer']+'/'+ref['revision'])
        value=reader.parse(result.store.read_object(ref['digest']))
        if result.index.get('requiredFeatures',[]) or value.get('profile')!='adaptiveplotter.drawing/1' or value.get('requiredFeatures',[]):
            keys.add('unknown-drawing:'+ref['digest']);return
        parent=value['parent']
        if parent['state']=='present':visit(parent['ref'],depth+1)
        elif parent['state']=='unavailable':keys.add('unknown-parent:'+ref['digest'])
        elif parent['state']!='none':keys.add('unknown-parent:'+ref['digest'])
        source=value['input']
        if source['state']=='unavailable':keys.add('unknown-input:'+ref['digest'])
        elif source['state']=='present':
            ref=source['ref'];keys.add('input:'+ref['issuer']+'/'+ref['revision'])
            inp=reader.parse(result.store.read_object(ref['digest']))
            if inp.get('profile')!='adaptiveplotter.image-input/1' or inp.get('requiredFeatures')!=[]:
                keys.add('unknown-input:'+ref['digest']);return
            photo=inp['photo']
            keys.add('photo:'+photo['issuer']+'/'+photo['revision'])
            record=reader.parse(result.store.read_object(photo['digest']))
            if record.get('profile')!='adaptiveplotter.photo/1' or record.get('requiredFeatures')!=[]:
                keys.add('unknown-photo:'+photo['digest']);return
            keys.add('photo-bytes:'+record['original']['object'])
            capture=record.get('captureFacts')
            if capture is not None:
                facts=reader.parse(result.store.read_object(capture['object'])) if capture['encoding']=='utf8-json' and capture['mediaType']=='application/json' else None
                known=(record.get('profile')=='adaptiveplotter.photo/1' and not record.get('requiredFeatures') and type(facts) is dict and not facts.get('requiredFeatures') and
                    {'photoID','label','capturedAt','pose','captureSessionID','imageSHA256'}<=facts.keys() and facts['imageSHA256']==record['original']['object'] and
                    type(facts['label']) is str and type(facts['capturedAt']) in (int,float) and facts['pose'] in ('Left','Front','Right'))
                if known:
                    # Flow capture facts use Foundation UUID spelling; canonical
                    # wire Photo references remain separately exact.
                    try:
                        reader.uuid_text(facts['photoID'],canonical=False)
                        session=reader.uuid_text(facts['captureSessionID'],canonical=False)
                        keys.add('capture-session:'+str(session))
                    except ValueError:keys.add('unknown-capture-session:'+capture['object'])
                else:keys.add('unknown-capture-session:'+capture['object'])
        elif source['state']!='none':keys.add('unknown-input:'+ref['digest'])
    visit(drawing);return keys


def same_json_value(left, right):
    """Compare full JSON values without Python's bool-as-integer equality."""
    if type(left) is dict and type(right) is dict:
        return left.keys()==right.keys() and all(same_json_value(left[k],right[k]) for k in left)
    if type(left) is list and type(right) is list:
        return len(left)==len(right) and all(same_json_value(a,b) for a,b in zip(left,right))
    if type(left) in (int,float) and type(right) in (int,float):return left==right
    return type(left) is type(right) and left==right


def task_index(source, source_asset, task_asset):
    """The export/read transformation preserves every original JSON field."""
    reader.require(source.get('profile')=='adaptiveplotter.exchange/1' and source.get('kind')=='result', 'task original result profile/kind')
    derived=dict(source);assets=list(source['assets'])
    for asset in (source_asset,task_asset):
        descriptor={k:asset[k] for k in ('object','byteLength','mediaType','encoding')}
        if not any(same_json_value(existing,descriptor) for existing in assets):assets.append(descriptor)
    derived.update(assets=assets,scope=task_asset)
    return derived


def inspect_task(result):
    scope=result.index.get('scope')
    if not isinstance(scope,dict) or scope.get('encoding')!='adaptiveplotter.drawing-evidence-task/1':return None
    reader.asset(result.store,scope)
    task=reader.parse(result.store.read_object(scope['object']))
    reader.require(task.get('profile')=='adaptiveplotter.drawing-evidence-task/1' and task.get('taskVersion')=='1' and task.get('requiredFeatures')==[], 'unsupported evidence task contract')
    contract=TASK_CONTRACTS.get(task['task'])
    reader.require(contract is not None and (task['inputContract'],task['labelContract'])==contract,'task input/label contract differs')
    reader.require(task['includedAsOf']==result.index['includedAsOf'] and type(task['extractorRevision']) is str and task['extractorRevision'],'task as-of/extractor differs')
    source=task['sourceIndex'];reader.asset(result.store,source)
    reader.require(source['encoding']=='adaptiveplotter.exchange/1','task original index encoding')
    original=reader.parse(result.store.read_object(source['object']))
    reader.require(same_json_value(task_index(original,source,scope),result.index), 'task carrier is not the exact allowed derivation of its original result index')
    reader.require(original['includedAsOf']==task['includedAsOf'], 'task original included-as-of differs')
    source_descriptors={}
    source_unsupported=[]
    envelope_shape('index',original,source_unsupported)
    for descriptor in original['assets']:
        h=descriptor['object'];reader.require(h not in source_descriptors or reader.asset_facts(source_descriptors[h])==reader.asset_facts(descriptor),'task original descriptor conflict')
        reader.asset(result.store,descriptor);source_descriptors[h]=descriptor
    # The original scope was replaced, so validate its original edge as well as
    # every original typed reference against precisely its original descriptors.
    validate_closure(result.store,original,source_descriptors,source_unsupported)
    rows=[];groups={};declared_splits={};selections=set()
    for entry in task['entries']:
        selection=entry['selection'];job=selection['job']
        encoded=json.dumps(selection,sort_keys=True);reader.require(encoded not in selections,'duplicate task selection');selections.add(encoded)
        reader.require(job in result.index.get('jobs',[]) and type(entry['eligible']) is bool and type(entry['exclusions']) is list and type(entry['limitations']) is list, 'task entry')
        split=selection['split'];reader.require(split in ('inspection','training','holdout') and type(selection['group']) is str and selection['group'], 'task group/split')
        reader.require(selection['group'] not in declared_splits or declared_splits[selection['group']]==split,'one declared task group crosses training/holdout splits')
        declared_splits[selection['group']]=split
        receipt=reader.parse(result.store.read_object(job['receiptDigest']))
        reader.require(entry['drawing']==receipt['drawing'],'task Drawing differs from receipt')
        keys=task_grouping_keys(result,receipt['drawing'])|{'declared:'+value for value in selection['relatedGroups']}
        reader.require(sorted(keys)==entry['groupingKeys'],'task source grouping keys differ')
        for key in keys:
            reader.require(key not in groups or groups[key]==(selection['group'],split), 'related task evidence crosses groups/splits')
            groups[key]=(selection['group'],split)
        ref=selection.get('snapshot');snapshot=None
        if ref:
            path=f"data/attempts/{ref['archive']}/{ref['run']}/{ref['sequence']}/attempt.json"
            reader.require(path in result.store.inventory and result.store.inventory[path][0]==ref['digest'],'task exact snapshot')
            snapshot=reader.parse(result.store.read_object(ref['digest']))
            reader.require(snapshot['job']==job and snapshot['drawing']==receipt['drawing'],'task snapshot binding')
        else:reader.require(receipt['disposition']=='refused','accepted task entry requires snapshot')
        expected_outcome=snapshot['state'] if snapshot else 'refused'
        reader.require(entry['outcome']==expected_outcome and entry.get('environment')==(snapshot['environment'] if snapshot else None),'task outcome/environment differs')
        expected_claims=[]
        assessment_selections=array(selection['assessments'])
        reader.require(len({json.dumps(r,sort_keys=True) for r in assessment_selections})==len(assessment_selections),'duplicate task assessment selection')
        for assessment_ref in assessment_selections:
            reader.require(type(assessment_ref) is dict and set(assessment_ref)=={'issuer','revision','digest'},'task assessment full typed reference')
            reader.uuid_text(assessment_ref['issuer']);reader.uuid_text(assessment_ref['revision'])
            reader.require(type(assessment_ref['digest']) is str and DIGEST.fullmatch(assessment_ref['digest']),'task assessment digest')
            path=f"data/assessments/{assessment_ref['issuer']}/{assessment_ref['revision']}.json"
            reader.require(path in result.store.inventory and result.store.inventory[path][0]==assessment_ref['digest'],'task assessment is not an admitted typed record')
            assessment=reader.parse(result.store.read_object(assessment_ref['digest']))
            reader.require(assessment.get('profile')=='adaptiveplotter.assessment/1' and assessment.get('ref')=={k:assessment_ref[k] for k in ('issuer','revision')},'task assessment typed identity differs')
            reviewer=assessment['reviewer'];answer=assessment['answer']['type']
            reader.require(any(t.get('kind')=='drawing' and t.get('ref')==receipt['drawing'] or t.get('kind')=='attempt' and t.get('ref')==ref for t in assessment['targets']),'task assessment target differs')
            kind='uninterpreted-claim'
            claim={'reference':assessment_ref,'kind':kind,'answerType':answer,'reviewerKind':reviewer['kind'],'reviewerID':reviewer['id']}
            if 'version' in reviewer:claim['reviewerVersion']=reviewer['version']
            expected_claims.append(claim)
        reader.require(entry['claims']==expected_claims,'task attributed claims differ')
        native_row=next((r for r in result.native_inspections if ref and (r['archive'],r['run'],r['sequence'])==(ref['archive'],ref['run'],ref['sequence'])),None)
        if task['task']=='adaptiveplotter.result-inspection/1':
            reader.require(split=='inspection' and entry['eligible'] and not entry['exclusions'], 'inspection cannot declare training labels')
        elif task['task']=='adaptiveplotter.aligned-residual/1':
            reader.require(not entry['eligible'] and entry['exclusions'], 'residual eligibility needs a registered aligned-label decoder')
        elif entry['eligible']:
            reader.require(native_row is not None and native_row['selectedRequirementsSupported'] and snapshot and
                native_row['environment'] in ('live','simulation') and native_row['environment']==snapshot['environment'] and
                snapshot['state'] in ('staged','running','cancelling','interrupted','failed','cancelled') and
                not original.get('requiredFeatures') and not any(k.startswith('unknown-') for k in keys),'interruption claim lacks known exact stage/frontier facts')
        independent_eligible=(task['task']=='adaptiveplotter.interruption-state/1' and split in ('training','holdout') and
            native_row is not None and native_row['nativeBindingVerified'] and native_row['programRelationSupported'] and
            native_row['selectedRequirementsSupported'] and snapshot is not None and
            native_row['environment'] in ('live','simulation') and native_row['environment']==snapshot['environment'] and
            snapshot['state'] in ('staged','running','cancelling','interrupted','failed','cancelled') and
            not original.get('requiredFeatures') and not any(k.startswith('unknown-') for k in keys))
        rows.append({'job':job,'snapshot':ref,'outcome':entry['outcome'], 'declaredEligible':entry['eligible'],
                     'independentTrainingEligibility':independent_eligible,'exclusions':entry['exclusions'],
                     'limitations':entry['limitations'] + (native_row['limitations'] if native_row is not None else ['Native payload interpretation is unavailable.'])})
    return {'profile':task['profile'],'id':task['id'],'task':task['task'],'taskVersion':task['taskVersion'],
            'inputContract':task['inputContract'],'labelContract':task['labelContract'],'extractorRevision':task['extractorRevision'],
            'modelRevision':task.get('modelRevision'),'modelRevisionUnavailableReason':task.get('modelRevisionUnavailableReason'),
            'entries':rows,'limitation':'Task claims remain attributed; this independent reader grants no physical residual labels.'}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path);parser.add_argument('--staging-parent',type=Path,required=True)
    parser.add_argument('--json', action='store_true', help='Emit bounded result inspection as JSON; supplies no readiness, retry or physical authority')
    args=parser.parse_args()
    result=import_carrier(args.source,args.staging_parent)
    if args.json:
        print(json.dumps(inspect_result(result), sort_keys=True))
    else:
        print('verified',result.staging,'drawings',len(result.drawings),'unsupported',result.unsupported)
