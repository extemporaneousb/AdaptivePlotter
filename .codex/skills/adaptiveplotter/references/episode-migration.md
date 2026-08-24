# Episode Migration Continuation Protocol

Use this procedure only for work governed by
`docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md`. `AGENTS.md` remains the Blackdog
lifecycle authority. The plan owns architecture, dependencies, deletion gates,
and landed status; `docs/CURRENT_EVIDENCE.md` owns actual results. Do not copy
either contract here.

## Reconcile before selecting work

1. Inspect the current branch, HEAD, dirty state, and `origin/main` relation.
2. Inspect Blackdog state. If an unfinished episode-migration task exists,
   follow its exact `next_action`; do not begin another package.
3. Read `docs/INDEX.md`, the execution plan's Work Ledger and Package Completion
   Contract, and the latest relevant Current Evidence entry.
4. Recheck the owning Product Contract and current Swift Architecture sections
   for the package. Read the operator protocol, button transitions, or hardware
   runbook only when the package changes those surfaces.
5. Treat chat, temporary files, old prompts, review notes, and Git history as
   context only. They cannot override current canonical documents.

## Select exactly one package

- If the user names a package, verify every dependency is landed `complete`.
- For an unscoped `continue episode migration` request, select the first
  `pending` ledger row whose dependencies are `complete`.
- A `blocked` row requires its documented external input or a canonical-plan
  change; do not work around it.
- The ledger never records `active`. Blackdog owns in-progress state.
- Do not combine packages merely because their files overlap. A package is one
  reviewable authority transfer with one rollback boundary.

Before application-code migration, `BASE-00` must record the attended known-good
Learning Path on the exact signed build and a pushed annotated tag. Software
tests cannot satisfy that operator-owned prerequisite.

## Compose the Blackdog task

The execution prompt must name:

- work-package ID, goal, and dependencies;
- current source owners and behavior to preserve;
- the exact authority transferred;
- affected observability non-negotiables;
- same-landing deletions and forbidden compatibility paths;
- focused, replay, simulation, UI, repository, and physical validation classes;
- done condition: canonical plan ledger and Current Evidence updated in the same
  landing, with physical work explicitly passed, failed, or skipped.

Use one Blackdog task/worktree. Do not create a parallel architecture branch,
worktree, task, or effect-capable shadow implementation outside that task.

## Implement from authority outward

1. Inventory the package's actions, guards, owners, ports, tasks, mode branches,
   persistence, evidence, UI consumers, and tests before edits.
2. Add or move the canonical owner and its typed contracts.
3. Route production and test callers through it.
4. Delete the superseded action/state/guard/task/effect/test/document path in
   the same package landing. A read-only shadow may compare results only when
   the plan explicitly allows it; it may issue no effect or authoritative write.
5. Enforce observability while the state/effect model is introduced. Do not
   defer refusal reasons, effect ownership/progress, runtime/UI revision
   comparison, external diagnostics, or incident export to cosmetic cleanup.
6. Preserve `MachineController`, `RunInterpreter`, camera, Vision, planning,
   persistence, and evidence authority unless this package explicitly changes
   one without leaving a parallel owner.

If the clean typed contract requires `Any`, string/reflection registries,
arbitrary effect closures, new `@unchecked Sendable`, duplicate operation
owners, or composite async escape hatches, stop at the package gate and update
the canonical plan before pursuing a different architecture. Never document an
alternate plan beside it.

## Validate and land

Run the narrowest focused tests first, then the package's replay, causal
simulation, UI actionability, forbidden-import/symbol/deletion scans, and normal
repository validations. Run SwiftPM commands sharing `.build` serially. Record
software, replay, simulation, controller, camera, operator, and physical claims
as separate evidence classes.

Before landing:

1. prove every same-landing deletion disposition;
2. update the package ledger row to `complete` or `blocked`—never `active`;
3. add the exact Blackdog task, validation results, skipped evidence, and
   remaining limitations to Current Evidence;
4. recheck documentation links and the single-plan rule;
5. follow Blackdog's exact landing `next_action` until complete;
6. verify the authoritative target branch and clean state after landing.

The next session starts by reconciling the landed ledger and Blackdog state
again. It does not rely on a prior assistant summary.
