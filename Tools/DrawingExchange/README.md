# Independent exchange reader

Run from the repository root:

```sh
python3 Tools/DrawingExchange/carrier.py path/to/exchange.zip --staging-parent /private/tmp --json
# TEST_PYTHON names the provisioned test interpreter.
"$TEST_PYTHON" -m unittest discover -s Tools/DrawingExchange -p 'test_*.py'
```

The reader and CLI runtime use only the Python standard library. The test suite's
schema cross-checks additionally require `jsonschema.Draft202012Validator` and
`jsonschema.FormatChecker`; set `TEST_PYTHON` to the provisioned interpreter that
provides them. An unprovisioned `python3` is sufficient for the CLI, but is not
guaranteed to run the full test suite. No runtime schema-package dependency is
introduced by those tests.

`import_carrier(source, staging_parent, *, limits=Limits(), cancelled=None,
fault=None)` accepts a closed BagIt directory or classic ZIP. It returns
`VerifiedCarrier(staging, index, store, drawings, unsupported, native_inspections)` only after integrity
and typed closure checks. Unsupported exchange major versions return opaque staged
bytes and no drawings. Unknown exchange requirements disable drawing operations;
unknown source/evidence semantics remain explicitly unsupported. Integrity is not
authentication. `--json` emits exact references, bounded native binding facts,
recorded execution frontiers, explicit unsupported semantics, and task scope when
present. It never grants readiness, retry, or physical-validity authority.
Unknown job disposition remains opaque even when referenced by a known attempt: exact
receipt/drawing links and snapshot-chain integrity still apply, while accepted-job
issuance semantics remain unavailable. Known refused receipts cannot have attempts.
Passing envelope checks supplies no production adapter or Library installation.

`native.py` recognizes the existing `adaptiveplotter.drawing-run-proposal/1`,
`adaptiveplotter.native-coverage/1`, `adaptiveplotter.raw-attempt-state/1`, and
`adaptiveplotter.raw-terminal-record/1` payloads. It checks the exact original
proposal/body/request/issuance/receipt/plan/options bindings, authored program
APCB hash, raw attempt/terminal relationships, cumulative frontiers, retained
possible-ink facts, every progress request/plan/frontier, exact retained raw
baseline/progress prefixes, and original media descriptors derived from raw
frames. The same bytes cannot acquire different dimensions, stride, orientation,
or pixel interpretation. Known malformed payloads
reject; unfamiliar encodings remain opaque and supply no native proof. Physical
plan canonical hashing and registration geometry remain explicitly unsupported.
Candidate identity must equal the exact authored Drawing digest. An unfamiliar
authored-to-execution compositor relation reports `nativeBindingVerified=false`
with its explicit limitation; a self-hashed replacement program proves no such
relation. A task's sender declaration remains inspectable and supplies no
independent training authority by itself. The interruption task independently
admits only recorded stage/frontier labels when exact same-source native binding,
selected requirements, original environment, stage, and source grouping are all
proved. Inspection and residual tasks never gain training labels from this check.
Environment comes from the original options asset; absence remains unknown.
Raw monotonic ticks have no recorded clock namespace, so cross-event elapsed
time is unavailable. No clock domain or current application mode is inferred.

`adaptiveplotter.drawing-evidence-task/1` scope freezes exact receipt, snapshot,
and assessment selections together with the original result index and its
included-as-of value, task/input/label contracts, extractor/model provenance,
exclusions, and source/parent/photo/canonical-capture-session grouping. Every
declared group is confined to one split, including disjoint source records.
Unknown ImageInput/Photo profiles or required features produce explicit unknown
grouping keys; their apparent photo/session fields cannot establish independence.
Inspection is available for refused,
cancelled, interrupted, missing-observation, or opaque evidence without treating
absence as a negative label. Answers stay attributed, uninterpreted claims until
their actual owning decoder accepts the entire question/target/answer contract;
familiar Flow answer names and reviewer strings alone grant no label semantics.
human preference, algorithm analysis, and synthetic/simulation evidence are not
interchangeable. Independent inspection recomputes known source grouping and
rejects conflicting training/holdout assignments and coherently rehashed forged
scope facts. Sender eligibility remains separate from independently recomputed
task eligibility. No aligned-residual label decoder is registered, and Rank
feedback remains a feature-only task with no physical geometry claim.

Task admission requires the complete outer index to derive from the carried
original index by only adding original-index/task asset descriptors and replacing
scope. All original requirements, descriptor dictionaries and unknown fields
remain part of this check, and the original scope/typed closure is validated.
Selected assessments require their full issuer/revision/digest, admitted
canonical typed path, matching record identity and no duplicates; an unindexed
CAS JSON object cannot become testimony through a digest alone. These checks
establish internal consistency, not external authenticity of the claimed original
publication.

The Swift task exporter copies all original evidence and media bytes and adds
the immutable task scope plus the original index asset. It owns no job, retry,
checkpoint, live store, or learner activation. To exercise actual Swift-produced
carriers in the independent reader, set `DRAWING_NATIVE_TASK_FIXTURE_OUTPUT` to a
new external directory when running `DrawingEvidenceTrainingTests`, then set the
same variable for the Python suite. This enables the cross-language test over
`native-task.zip`, `native-interruption-task.zip`, `session-task.zip` and
`disjoint-task.zip`, including coherently hashed eligibility, original-index,
capture-session and declared-group holdout forgeries. `ADAPTIVEPLOTTER_RESULT_FIXTURE_OUTPUT`
from the native result suite supplies `native-large-terminal.zip` for the separate
actual-owner record-size control. Without those explicit
fixture directory the cross-language case reports a skip; synthetic binding
tests still run and make no Swift-owner or physical-plan validation claim.

The original source is never modified. A ZIP is copied unchanged to
`<staging>/incoming.zip` before verification. Directory files are copied with
no-follow descriptor traversal and pre/post identity checks. Every failure retains
the private staging directory and exposes its path as `exception.staging`.
Cancellation and injected write faults retain partial staged bytes. Staging has no
catalog visibility and is deliberately not auto-deleted. The caller owns cleanup.

Known v1 envelopes enforce required object fields and concrete scalar/container
types before semantic admission. Boolean values are never integer sequences or
unknown enum strings. Unknown string enums remain unsupported while known sibling
references and assets are still validated. Reviewer, question and producer facts
are checked explicitly without a runtime JSON Schema dependency. Unknown optional
frontier fields remain opaque; only the four schema-defined frontier keys are
interpreted as evidence declarations.

ZIP policy: single-disk, classic ZIP only; methods 0 (stored) and 8 (raw DEFLATE);
flags 0 or UTF-8 bit 11; versions through 2.0. Encryption, data descriptors, ZIP64,
prefixes, local gaps, overlaps, trailing compressed junk, and unsupported extra
fields are rejected or reported as `UnsupportedFormat`. Extended timestamp and
Unix UID/GID extras are accepted. EOCD comments are allowed; bytes beyond the
comment are rejected. Local and central names, flags, method, DOS time/date, sizes and CRC must
agree. Central extent and every compressed range are checked independently of
`zipfile`. CRC, raw DEFLATE EOF, consumed bytes and actual expanded length are
verified while streaming. Stored and deflated empty directory entries validate their complete stream, size and CRC.
Directory entries are allowed; Unix regular permission
bits with zero type bits are accepted for the frozen fixture. Links, special files,
file-as-parent conflicts, duplicate paths and NFC/case-fold collisions are refused.

Default limits are 100,000 files, 32 GiB per file, 128 GiB expanded bytes, expansion
ratio 10,000, 1 MiB streaming chunks, 8 MiB JSON records, 32 MiB manifests.
Only `adaptiveplotter.raw-terminal-record/1` has a separate 256 MiB JSON cap;
generic envelopes retain the 8 MiB bound. Materializing unique object bytes is
also bounded to 256 MiB per package, including these typed owner records.
Classic
ZIP transport has its inherent 32-bit sizes and 16-bit entry count; use directory
transport for larger packages. Paths are NFC UTF-8, at most 4,096 bytes total and
255 per component, with no empty/dot/dotdot components, absolute prefix, backslash,
colon or control characters. BagIt requires exactly the two specified LF lines,
lowercase SHA-256 manifests, two spaces before each path, LF line endings, exact
payload/tag closure and no fetch.txt.

`FileBackedStore` exposes `read_object(digest, maximum)`, `object_size(digest)`,
`open_object(digest)` and typed path checks to the old `reader.drawing` and
`reader.image_input` APIs. The old `root/objects/<digest>` compatibility path is
retained. Record/program bytes are returned unchanged; APCB hashes are independently
checked. No `[digest: bytes]` media dictionary is built. Staged file fingerprints
are checked on subsequent reads; this is retained private staging, not a concurrent
mutable storage service.

Read passes are explicit: directory import reads each incoming file once while
copying/hashing; ZIP import reads once to preserve the incoming archive, then reads
compressed bytes once while expanding, hashing and checking CRC. BagIt verification
compares the recorded hashes rather than rereading all payloads. JSON semantic
admission reads bounded records/programs as needed; recursive shared ancestry may
reread bounded records. Asset metadata checks use file length, not media reads.
PNG validation performs a separate streaming chunk/CRC container pass. JPEG uses a
bounded marker/header walk and final EOI check. Neither path decodes pixels or
grants supported source semantics: container/header proof is weaker than bounded
actual decode proof. Raw pixels and arrays validate dimensions, strides, scalar
width, byte order and exact lengths without materializing media. Existing reader
limits remain 8,192 per image dimension and 32 Mi pixels; encoded inputs are at
most 64 MiB. No pixel decoder is invoked during archive import.

Repeated exact index references and descriptors with identical modeled facts are
idempotent; the original JSON arrays are preserved. Descriptor equality compares
known fields, including optional field presence and nested dimensions, pixel/array
layouts and decoded digest facts. Vendor-only differences remain in the original
bytes and do not create conflicts. A missing optional known fact is not enriched
from another repeated descriptor. Conflicting identity/digest bindings and contradictory
known descriptor facts are refused. Filesystem entries and manifest lines must
still be unique. Directory case-collision tests explicitly skip when the temporary
volume cannot represent both names; this is a host limitation, not exercised
reader rejection. Coherently manifested ZIP case and component-alias controls run
on every host and exercise the collision verifier independently of that limit.

Every canonical included typed record is validated even when it is not a selected
index root, as in a feedback capsule that retains an authored drawing. Unclaimed
noncanonical payload files cannot gain admission merely by sharing another
record's digest. Unknown dispatch strings preserve earlier possible-ink facts;
only a known `not-dispatched` claim contradicting retained possible ink rejects.
Unknown dispatch never proves clearance or grants result interpretation.

A known current attempt may refer to an unfamiliar-major immutable receipt or
predecessor. Those bytes remain opaque; the verifier does not require v1 fields
from their future bodies or assert complete understood result semantics. Every
known current drawing, intent, coverage, terminal, plan and assessment reference
still resolves strictly. An opaque receipt never implies acceptance/refusal or
issuance, and an opaque predecessor never implies a seal, dispatch or frontier.
