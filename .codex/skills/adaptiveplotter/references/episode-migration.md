# Episode Migration Execution Protocol

Use this procedure only for work governed by
`docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md`. `AGENTS.md` remains the Blackdog
lifecycle authority. The plan owns architecture, package dependencies,
validation/deletion gates, and landed status. The vocabulary document owns
target definitions, and `docs/CURRENT_EVIDENCE.md` owns actual results. This
procedure owns only audit, prompt compilation, and package execution mechanics.
The separate `$run-multi-agent-wave` skill owns deterministic selection and
multi-agent coordination mechanics.

## Explicit modes

There is no unscoped continuation mode. Automatic selection is available only
through `$run-multi-agent-wave`, which selects one eligible `repository`,
`software`, or `gate` row in canonical ledger order and then uses the same named
package execution path.

- `audit episode migration` is read-only. It reports reconciliation, dependency,
  and contract state and then stops.
- `compile episode package <ID>` is read-only. It returns the exact prompt for
  the named package as a preview and then stops.
- `execute episode package <ID>` is the only ordinary mutation mode. It executes
  one named `repository`, `software`, or `gate` package.
- `$run-multi-agent-wave` is the automatic mutation mode. It reconciles active
  claims first, then selects at most one eligible ordinary package and acts as a
  coordinator under its complete wave-coordination reference. It cannot change
  package scope or execution class.
- An `attended-physical` package requires a direct request that explicitly names
  attended physical execution and the package ID. Read the Attended Hardware
  Runbook first. The mechanism must remain continuously attended with the power
  cutoff reachable.
- A `remote-git` package requires a direct request that explicitly names the
  remote-Git package and separately authorizes its exact push. Tag creation and
  branch publication are separate packages and permissions; neither remote push
  is implied by code, documentation, or physical execution.

Audit and compile modes never write a prompt file, call `task begin`, edit Git,
touch a controller/camera, create a tag, or contact a remote.

## Reconcile before any episode mode

1. Inspect current branch, HEAD, dirty state, worktree role, and
   `main...origin/main` relation. Episode execution must start in the normal
   primary workspace on branch `main`, with a clean tracked worktree, so
   Blackdog would record canonical `main` as the target. Report and stop on a
   mismatch; never switch branches automatically.
2. Inspect repository-wide Blackdog `summary --json`, not only the current
   checkout. If any unrelated unfinished task exists, report its exact
   structured `next_action` and stop in audit, compile, and named execution;
   named-package execution is not authority to advance, cancel, land, or clean
   unrelated work. If the sole unfinished task is already the explicitly named
   package, execute mode may resume it only when its Blackdog prompt replay
   identifies the same ledger ID and the current request explicitly authorizes
   continuation. Wave mode instead follows its coordination reference: it may
   resume verified recoverable ordinary-package work through Blackdog's exact
   action, or message an active owning agent for one explicit bounded offload.
   It never cancels, replaces, or guesses that a claim is stale. Audit/compile
   modes always report and stop without executing it.
3. In audit and wave modes, read the complete ledger, Package Completion
   Contract, exact gate catalog, and latest Current Evidence. In compile/named
   execute mode, read only the named package row, its dependency rows, those
   same contracts, and the latest evidence relevant to that package.
4. Read Episode Architecture Vocabulary. Read Product Contract and current Swift
   Architecture only for the named package's owners and preserved behavior.
   Read the current operator protocol, UI transitions, or hardware runbook only
   when that package changes or validates those surfaces.
5. Treat chat, temporary files, old prompts, review notes, critic output, and Git
   history as context only. They cannot override canonical documents.

Audit mode reports these facts and stops. It does not call a pending row
“eligible for execution” unless the row has complete dependencies, an allowed
execution class for the requested mode, and fully expanded exact gates.

## Validate the named or selected package

- The package ID must exist exactly once in the canonical ledger.
- Every dependency must be landed `complete`; Blackdog operation success alone
  does not satisfy a dependency.
- Every required gate must resolve to an exact command or evidence procedure.
  An undefined gate makes the package ineligible.
- One package must represent one reviewable atomic outcome and one
  rollback/evidence/decision boundary. A `software` cutover transfers exactly
  one product authority with same-landing deletion. A `repository`,
  `attended-physical`, `remote-git`, or `gate` package transfers no product
  authority. If inventory disproves the recorded boundary, stop and amend the
  canonical ledger in a dedicated repository package; do not silently rescope
  execution.
- `EA-01` may add exact owners, symbols, package scan data, and current-source
  characterization commands to the canonical ledger. It cannot rename or
  replace the target focused-suite names or gate commands. A lower-reasoning
  executor cannot choose either set.
- A `blocked` row requires its recorded external input or a canonical-plan
  correction. Do not work around it.
- The ledger never records `active`; Blackdog owns in-progress state.

`EA-01` is intentionally available before attended baseline work. No
application-code migration may begin until both the inventory and exact
`BASE-03` published/tagged baseline dependency required by its row are complete.

## Compile the exact execution prompt

The first line is exactly
`AdaptivePlotter episode WorkPackage: <ID>`. This stable marker is part of the
Blackdog replay identity; package-specific publication procedures may verify it
but may not infer it from a task title or caller-supplied argument.
For `BASE-03`, the second line is exactly
`AdaptivePlotter tested baseline commit: <TESTED-BASELINE-COMMIT>`, with the
placeholder replaced by the sole 40-character lowercase commit recorded by
BASE-01 as `TESTED-BASELINE-COMMIT: <commit>` in Current Evidence.

The prompt copies, without summarizing away constraints:

- package ID, class, atomic outcome, dependencies, and exact gate commands;
- current source owners and behavior to preserve;
- the atomic package outcome and, for a software cutover, its one authority
  transfer and target seam;
- affected observability non-negotiables;
- every same-landing deletion and forbidden compatibility path;
- exact focused, replay, simulation, UI, repository, and physical evidence
  boundaries;
- completion hierarchy: Blackdog operation versus package versus migration;
- done condition: authoritative-target landing, all required gates passed,
  deletions proved, Current Evidence updated, and the ledger row updated in the
  same landing.

The prompt states that `failed`, `skipped`, or missing required evidence cannot
satisfy a gate. It states “package `<ID>` complete; migration remains incomplete”
unless the final global condition is actually met.

Compile mode displays this prompt only and stops. It creates no Blackdog task or
repo artifact.

## Execute from authority outward

1. Re-run reconciliation immediately before `task begin`.
2. Create the mode-0600 request and execution-prompt files required by
   `AGENTS.md`. Named execution uses the compiled prompt verbatim. Wave execution
   preserves the complete compiled prompt as its first section and appends the
   required `Multi-agent coordination overlay`; it does not edit or weaken the
   package prompt.
3. Start exactly one Blackdog task and edit only its returned task workspace.
4. Inventory the package's named current owners and consumers before edits.
5. Add or move the canonical owner and typed contracts, then route production
   and test callers through it.
6. Delete the superseded intent/state/guard/task/effect/port/test/document path
   in the same landing. A read-only shadow is allowed only when the plan names it
   and it issues no effect or authoritative write.
7. Add refusal, effect ownership/progress, runtime/UI revision comparison,
   external diagnostics, and incident evidence at the package seam; do not defer
   them as presentation cleanup.
8. Preserve `MachineController`, `RunInterpreter`, camera, Vision, planning,
   persistence, and evidence authority unless the package explicitly transfers
   one responsibility and deletes the old owner.

If the typed contract requires `Any`, string/reflection registries, arbitrary
effect closures, new `@unchecked Sendable`, duplicate operation owners, or
composite async escape hatches, stop at the package gate and update only the
canonical plan. Never add an alternate plan.

## Validate, assess, and land

Run the package's exact focused checks first, then its replay, causal simulation,
UI actionability, deletion/forbidden-import/direct-port scans, and repository
gates in the recorded order. SwiftPM commands that share `.build` run serially.
Record software, replay, simulation, controller, camera, operator, and physical
claims as separate evidence classes.

Before landing:

1. prove every same-landing deletion disposition;
2. confirm every required gate passed—never failed, skipped, or missing;
3. add exact validations and limitations to Current Evidence;
4. update the ledger row to `complete`, or remove all partial transfer work and
   leave/update it as `blocked`;
5. run `make docs-check` and recheck the single-plan rule;
6. follow Blackdog's structured `next_action` exactly through landing;
7. verify the recorded target branch and clean state after landing.

An independent critic finding is non-authoritative until integrated into the
owning canonical document and the candidate is revalidated. Critic reports,
prompts, and alternate diagrams are never checked in. The next session starts
with read-only audit; it does not rely on a prior assistant summary.
