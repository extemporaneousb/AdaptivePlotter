# AdaptivePlotter Document Routing

This is the startup routing catalog for repository work. Read `AGENTS.md` and
this file first, then load only the documents relevant to the current request.
Do not load every linked document by default.

## Current authority

- Operator journey, UI vocabulary, build, test, signing, or launch:
  [README](../README.md).
- Product boundary, motion authority, safety, evidence classes, accepted
  artifacts, simulator isolation, or learning direction:
  [Product Contract](PRODUCT_CONTRACT.md).
- Package topology, runtime ownership, dependency direction, controller/camera
  seams, coordinates, registration, or architectural refactoring:
  [Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md).
- Boundary Discovery, clear-view registration, visibility-target work,
  observed drawing trials, Stop/Cancel semantics, or recovery sequence:
  [Discovery and Observed-Trial Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md).
- Current software, automated, environment, controller, camera, human, pen, or
  observed-ink validation claims:
  [Current Evidence](CURRENT_EVIDENCE.md).
- Future scope, milestones, experiment selection, or adaptive-drawing planning:
  [Roadmap](ROADMAP.md).
- Attended controller, camera, motion, pen, or observed-ink verification:
  [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md), together with
  Current Evidence.

## Selection rules

- A focused implementation normally needs the directly owning document plus
  the relevant source and tests, not the entire catalog.
- Read Product Contract when a change could alter authority, safety, evidence,
  or learning semantics.
- Read Architecture when ownership or dependency direction may change.
- Read the operating protocol for Learning Path or physical-action sequencing.
- Read Current Evidence before reporting what is verified now.
- Hardware documents authorize no motion by themselves; attended physical
  actions still require explicit user authorization.
- Git history and Blackdog replay artifacts retain historical decisions and
  execution prompts. They are not current product authority.
