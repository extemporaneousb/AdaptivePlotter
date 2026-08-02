# AdaptivePlotter Repository Seed

This directory is the clean root of the independent AdaptivePlotter Git and
Blackdog project. It is not a migration checkout or a worktree of the existing
Plotter repository.

The next agent's job is to create a new Swift 6 macOS product here from a blank
repository while preserving the causal, safety, evidence, and replay contracts
in these documents. The existing Plotter repository is forensic evidence only.
It is not a source tree to copy, port, wrap, or retain for compatibility.

## Agent directive

Before creating product code:

1. Read this README completely.
2. Read [Feasibility Review and Binding Amendments](docs/FEASIBILITY_REVIEW_AND_BINDING_AMENDMENTS.md).
3. Read [Architecture Assessment and Design](docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md).
4. Read [Sequential Rebuild Plan](docs/SWIFT_ADAPTIVE_PLOTTER_SEQUENTIAL_REBUILD.md).
5. Resolve any remaining contradiction in documentation before implementation.

The feasibility amendments are binding where they clarify or override the two
original documents. The architecture owns the target design. The sequential
plan owns execution order. This README owns new-repository bootstrap and source
separation.

Do not treat the documents as suggestions to be summarized and then ignored.
Turn their types, invariants, evidence requirements, phase gates, and deletion
rules into the repository's actual structure, tests, and implementation.

## Mission

Build one native macOS application process implementing checkpointed adaptive
visual-feedback drawing control:

```text
logical vector stroke
  -> bounded machine and pen plan
  -> execute
  -> lift and move the complete armature clear
  -> acquire fresh stable camera evidence
  -> observe actual ink
  -> compare intended, predicted, and observed geometry
  -> correct identifiable current state
  -> accept slow model changes only from sufficient independent evidence
  -> replan only work that has not been commanded
```

The live product is Swift-only. Python may later exist only as an offline reader
of immutable exported run bundles. It may not participate in camera capture,
serial control, safety, planning, execution, model selection, persistence
authority, replay truth, or UI gating.

## New-repository boundary

The source repository is:

```text
/Users/bullard/Projects/Plotter
```

The architecture bundle was taken from clean `main` at:

```text
4f5478e0230cb8028b13cf3ebf0e83b631bffe1c
```

The source repository may be inspected read-only for hardware transcripts,
configuration hypotheses, camera techniques, failure cases, and small curated
fixtures. Never copy its `.git`, Blackdog control state, virtual environments,
artifacts tree, bridge, Python live product, Swift bridge client, workflow UI,
DTOs, compatibility paths, or source layout into this repository.

The original architecture document SHA-256 is:

```text
52f63383f9660fbb192499e2563a91e1a2b286adc59641651fe97bfb80dd45a6
```

The original sequential plan SHA-256 is:

```text
350f6101f525a37e6a9d9cfb48d4438c807d805ff643fe60bed1d57874782e58
```

Those hashes identify the reviewed inputs. This directory adds binding
amendments without silently rewriting the originals.

## Repository bootstrap

When explicitly asked to initialize the project:

- initialize a new Git repository with `main` as its primary branch;
- install/configure Blackdog as a new project if the user selects that workflow;
- do not copy Blackdog metadata or task history from the source repository;
- add a repo-local `AGENTS.md` that routes agents to this README and the three
  architecture documents;
- establish native Swift build, test, format, and validation commands before
  adding live machine behavior;
- keep every retained implementation phase in its own branch-backed task
  workspace and land only after its exit evidence is complete.

The intended high-level structure is:

```text
AdaptivePlotter/
  README.md
  AGENTS.md
  docs/
  AdaptivePlotter.xcodeproj/
  Sources/
    PlotterModel/
    PlotterRuntime/
    PlotterApp/
  Tests/
    PlotterModelTests/
    PlotterRuntimeTests/
    PlotterAppTests/
    PlotterTestSupport/
  Fixtures/
```

This is a dependency and ownership layout, not permission to create empty
layers. Create only the files needed by the current phase. The exact Xcode group
layout may be adjusted if target dependencies and ownership remain unchanged.

## First implementation boundary

Start with Phase 1 forensic evidence and repository contracts. Do not copy
legacy implementation as scaffolding. Phase 2 creates the native targets and
passive controller path. Phase 4 must establish the narrow armature-viewability
geometry described in the binding amendments before Phase 5 draws the first
training stroke.

There is no separate throwaway ink-recognition architecture spike. For initial
feasibility, assume that a sufficiently large isolated green line on clean white
paper is detectable. The unresolved physical question is whether the complete
pen, holder, linkage, and servo assembly can be moved to a bounded pose where it
does not occlude the observation region.

## Non-negotiable outcome

The new repository is successful only if it produces a native product in which:

- camera, controller, safety, planning, execution, model authority, evidence,
  ledger, replay, and UI gating are native typed Swift boundaries;
- actual ink, not cap motion or controller completion, determines drawing
  evidence;
- ambiguous or controller-completed-but-unverified work is never automatically
  redrawn;
- every physical action and decision is durably attributable and replayable;
- the operator UI renders authority and blockers but does not recreate them;
- no legacy live Python, HTTP bridge, DTO mirror, compatibility alias, or hidden
  alternate execution path enters the repository.

## Suggested instruction to the next agent

Use this when handing the directory off:

> Initialize a brand-new repository in this directory. Read README.md and all
> documents under docs/ in the stated order. Treat the feasibility amendments
> as binding. Build the repository and execution contracts for the Swift-only
> AdaptivePlotter redesign; do not copy or port the legacy Plotter product. If
> Blackdog is available, install it as a new project and execute the sequential
> plan through separate gated tasks. Begin with Phase 1 and stop at every
> physical or evidentiary exit gate.
