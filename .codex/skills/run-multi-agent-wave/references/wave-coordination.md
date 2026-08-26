# Multi-Agent Wave Coordination Protocol

This reference owns selection and coordination mechanics only. It cannot change
a WorkPackage's scope, dependencies, execution class, authority transfer,
deletions, gates, or evidence boundary. One wave is exactly one canonical
WorkPackage executed in exactly one Blackdog task worktree. Multiple workers may
operate inside that boundary; multiple package tasks are not one wave.

## 1. Reconcile authority and reservations

Start in the normal primary workspace. Consume the mode-0600 hash-bound capsule
with `./.VE/bin/python Scripts/episode_wave_capsule.py consume`. If it is missing
or stale, create it mechanically and consume it again. The consumer validates
the primary `main` HEAD, empty Git status, authority-file and section hashes,
ledger/evidence contract, literal-order frontier, and repository-wide Blackdog
claim set. Use its exact package-specific pointers instead of loading the whole
ledger, evidence history, vocabulary, and this protocol into model context.
Canonical documents remain authority; the capsule grants no permission and
caches no Blackdog `next_action`.

Treat every Blackdog `next_action` as the sole lifecycle authority. Execute its
exact `argv` when it is a command, choose only a complete emitted alternative,
and stop on `blocked` or `complete`. Do not infer ownership or failure from age,
process absence, a task title, prose, or an apparently pristine worktree.

When an unfinished claim exists:

- First execute any exact owner-task finalization action that Blackdog requires.
- Verify the task's prompt replay and package marker. Never adopt a task whose
  replay cannot be bound to exactly one ledger row.
- If the task is failed or interrupted and Blackdog exposes a recoverable path,
  resume it as coordinator only when its row is `repository`, `software`, or
  `gate`, its dependencies are still complete, and the package boundary remains
  canonical. Follow only the emitted recovery action. A physical or remote-Git
  task still needs its separate current authorization.
- If another agent actively owns the claim, do not start or recover a second
  task. Use the available Codex task/thread or agent messaging capability to ask
  that coordinator for a bounded offload. The request asks for one independent
  unit, the exact task worktree, file and semantic leases, preserved behavior,
  done condition, and return format. Join only after the owner explicitly grants
  it. If messaging is unavailable, the owner declines, or no safely disjoint unit
  exists, report the task and owner and stop.
- An offload worker follows the existing coordinator's boundary and never takes
  over Blackdog or Git lifecycle authority.

Consume the capsule again immediately before `task begin`. If its live claim
set or any other binding changed, regenerate and restart claim resolution. The
Blackdog `task begin` result remains the atomic reservation.

## 2. Select one eligible row

Only when no unfinished claim exists, examine rows in their literal order in the
canonical ledger. A row is eligible only when all of these are true:

1. its status is `pending`;
2. its class is `repository`, `software`, or `gate`;
3. every dependency row is landed `complete`;
4. every required gate resolves to its exact command or evidence procedure;
5. Current Evidence and the package contract contain no unresolved blocker,
   contradictory completion claim, missing external input, or disproved atomic
   boundary.

Select the first eligible row. Do not choose by convenience, apparent size, or
opportunity for parallelism. Do not skip an earlier canonical dependency by
starting one of its descendants. The selection authorizes only that row. It
does not authorize attended controller/camera/motion/Pen work, observed-ink
claims, branch publication, tag creation, a remote push, or another package.

If no row is eligible, report the exact frontier: the first incomplete row or
dependency chain, its execution class, gate/blocker, and the authorization or
canonical correction required. If every row is complete, report migration
completion and start nothing.

Run `$adaptiveplotter execute episode package <ID>` for the selected row. The
Blackdog `task begin` is the atomic reservation. If another caller wins the
claim, discard no work and return to section 1.

## 3. Compose the coordinator prompt

Use the complete compiled package prompt as the first prompt section without
deleting, weakening, or paraphrasing its constraints. Append a section titled
`Multi-agent coordination overlay` containing all of the following rules:

- You are the sole coordinator for this package. Do not make implementation
  edits or run build, test, formatter, source/document generator, or validation
  commands. After verified landing, the required capsule-creation command is
  the sole workflow-metadata generation exception.
- At most four agents are active at once: this one coordinator and no more than
  three workers or critics. Editing, validation, documentation, and critic
  agents all count against the same three-subagent budget. Use fewer when leases
  are not provably disjoint, and finish a worker before dispatching the required
  fresh critic when all slots are occupied.
- You alone own Blackdog lifecycle, work decomposition, leases, acceptance,
  retasking, completion assessment, and landing. Workers never create or mutate
  Blackdog tasks, branches, worktrees, commits, stashes, rebases, merges,
  landings, cleanup, tags, or remote refs, and never spawn child agents.
- All workers use the one returned task worktree. Filesystem changes are already
  shared; do not ask for patches to be blindly reapplied or merged.
- Before dispatch, record task ID, target branch, base HEAD, worktree path,
  `git status --short`, the complete pre-existing diff/untracked set, and content
  identities for files about to be leased. Existing changes are a protected
  baseline, not disposable residue.
- Decompose the package into bounded, independently verifiable units. Give each
  worker one outcome, explicit in-scope files and symbols, preserved authority,
  same-landing deletion obligations, forbidden actions, validation permission,
  and done condition. Demand concise updates only at block, handoff, or material
  scope discovery.
- Issue exclusive file leases and semantic-owner leases. No two live workers may
  write the same file, even at different symbols. If disjointness is not
  provable, serialize the units. `Package.swift`, canonical episode documents,
  package checkers, shared test support, and `OperatorWorkspace.swift` have one
  serial integrator whenever touched.
- Assign exactly one serial documentation integrator. Documentation is package
  implementation, not cleanup: before landing it updates the ledger row with
  task identity and truthful status, the Current Evidence gate row and detailed
  validations/limitations, current architecture when as-built ownership or
  topology changed, and every routed canonical document affected by behavior,
  operator flow, or evidence changes. Record reviewed/no-change dispositions for
  the remaining routed documents in the accepted-slice register; do not check in
  a separate report.
- Editing workers re-read current file content immediately before editing and
  compare it with their entry identity. If the file or assigned authority changed
  outside their own edits, they stop and report instead of overwriting. They do
  not run repository-wide formatters, generators, or broad mechanical rewrites
  unless that exact operation was leased.
- Nobody uses destructive or history-rewriting recovery such as `git restore`,
  `git checkout --`, `git reset`, `git clean`, ours/theirs conflict selection,
  force updates, or whole-file replacement that discards unrelated edits.
- Maintain an accepted-slice register. For every accepted handoff, inspect the
  actual current diff and record paths, symbols/authority, deletions, proof, and
  validations. Every later handoff must preserve all accepted slices and may not
  recreate, bypass, or revert them.
- Editing stops before validation begins. Grant one validation lease at a time;
  first wait for every editing worker to return and revoke every editing lease.
  All SwiftPM/build/test commands run serially. A validation worker runs the
  exact package gates and returns exact commands and outcomes. No validation
  runs against a changing tree.
- After integration and required gates, dispatch a fresh-context read-only critic
  against the actual candidate worktree. The critic checks the compiled package
  outcome, authority transfer, deletions, preserved behavior, evidence classes,
  package scope, accepted-slice register, and final diff. Findings name the
  requirement, path/symbol, evidence, and responsible lease.
- Classify every handoff and critic result as `ACCEPT`, `RETASK`, or `REJECT`.
  Retask the responsible worker for any material gap, then repeat affected gates
  and the fresh critic. Commentary, confidence, or a clean compile is not proof
  of completeness.
- Before landing, require a quiescent tree, inspect the complete diff and
  untracked set, prove every deletion/forbidden-path scan, reconcile Current
  Evidence and ledger status, and verify that no protected baseline or accepted
  slice disappeared.
- If the target becomes stale, stop workers. Execute only Blackdog's exact emitted
  stale-recovery action; never resolve with ours/theirs, reset, force, or skipped
  validation. Re-establish content identities, inspect the rebased diff, and
  repeat required gates and critic review before normal landing.

## 4. Worker assignment and status contract

The assignment names:

- package ID and one bounded outcome;
- exact task worktree;
- leased files, symbols, and semantic authority;
- entry HEAD plus relevant protected-baseline identities;
- behavior to preserve and deletion/consumer-proof obligations;
- allowed commands and whether the worker holds the editing or validation lease;
- forbidden lifecycle, Git-mutation, hardware, remote, and child-agent actions;
- done condition and this return schema.

Workers return only:

```text
STATUS: ACCEPT_CANDIDATE | BLOCKED | FAILED
ASSIGNMENT: files, symbols, authority, and deletion obligations
BASELINE: entry HEAD and protected-diff/content identities
CHANGED: path -> symbols and outcome
DELETED: path/symbol -> consumer or zero-match proof
PRESERVED: required behavior and authority boundaries
VALIDATION: exact command -> exit/result/count, or not run
OUTSIDE_SCOPE: none, or exact unexpected paths
RISKS: unresolved correctness or integration concerns
TREE: final git status --short
CONFIRM: no lifecycle/Git/hardware/remote/child-agent action and no unassigned edit
```

Status text is evidence routing, not acceptance. The coordinator verifies the
shared worktree directly before updating the accepted-slice register.

## 5. Completion

The coordinator lands only after the canonical package completion contract,
every exact gate, deletion proof, evidence update, ledger update, accepted-slice
preservation check, and fresh critic pass are satisfied. Blackdog operation
success is not package completion. Follow its exact actions through landing and
cleanup, then prove the landed commit is current `main`, the primary workspace
is still on `main`, `git status --short` is empty, repository-wide Blackdog state
has no unfinished wave task, and no disposable task worktree remains. Generate
the successor capsule mechanically with `Scripts/episode_wave_capsule.py create`;
do not use a successor reconnaissance agent. Report `package <ID> complete;
migration remains incomplete` unless the execution plan's final global condition
is also proved.
