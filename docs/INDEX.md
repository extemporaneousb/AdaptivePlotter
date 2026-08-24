# AdaptivePlotter Document Routing

Read `AGENTS.md` and this catalog first, then load only the authority relevant
to the task.

## Documentation inventory and authority

| Document | Status and exact responsibility |
| --- | --- |
| [README](../README.md) | Operator and contributor orientation: current product journey, mechanical/evidence summary, build/test/launch commands, and links to authority. It does not own detailed product or architecture semantics. |
| [Document Routing](INDEX.md) | This exhaustive inventory and routing table. It assigns each document one noncompeting responsibility and owns the single-plan documentation rule. |
| [Product Contract](PRODUCT_CONTRACT.md) | Current durable product authority: safety, evidence classes, accepted artifacts, operator semantics, simulation limits, and episode-migration/observability non-negotiables. |
| [Learning Path Operating Protocol](DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md) | Exact current operator/runtime sequence, dependencies, Stop, ambiguity, recovery, reset, and causal-simulator behavior. It is current behavior, not the target migration plan. |
| [Learning Path Button Transitions](LEARNING_PATH_BUTTON_TRANSITIONS.md) | Exhaustive current Learning Path controls and state destinations. Its Mermaid diagram is the current UI interaction contract, not a target architecture proposal. |
| [Swift Architecture](SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md) | Current as-built package topology, owners, data flow, and validation shape. It must not claim that planned episode packages already exist. |
| [Episode Architecture Vocabulary](EPISODE_ARCHITECTURE_VOCABULARY.md) | Sole authority for target type names, definitions, relationships, forbidden synonyms, and the current-name/target-name boundary. It does not own migration order. |
| [Episode Architecture Execution Plan](EPISODE_ARCHITECTURE_EXECUTION_PLAN.md) | Sole target architecture, migration order, non-negotiable observability, structural/deletion gates, and landed-work ledger. |
| [Current Evidence](CURRENT_EVIDENCE.md) | Canonical ledger of what was actually implemented and verified. Current package-gate evidence appears first; clearly dated historical sections preserve evidence history without claiming strict date order or current design authority. Software, simulator, controller, and attended physical claims remain separate. |
| [Attended Hardware Runbook](ATTENDED_HARDWARE_RUNBOOK.md) | Human-attended physical validation procedure and evidence-record requirements. |
| [Roadmap](ROADMAP.md) | Unfinished product and experimental work only. It points to the execution plan for architecture migration and cannot redefine its sequence. |
| [`AGENTS.md`](../AGENTS.md) | Repository/Blackdog lifecycle contract. It governs how work begins, lands, and is validated; it does not own product design. |
| [AdaptivePlotter skill](../.codex/skills/adaptiveplotter/SKILL.md) | Thin repo-local operating overlay. It exposes separate audit, named-package prompt compilation, and named-package execution modes without duplicating architecture or lifecycle contracts. |
| [Episode-migration execution protocol](../.codex/skills/adaptiveplotter/references/episode-migration.md) | Focused mechanics for read-only reconciliation, named-package validation, prompt compilation, replacement, validation, and landing. It never selects an unnamed package and owns no architecture or package status. |

## Selection rules

- Read Product Contract for authority, safety, persistence, evidence, model
  semantics, or observability requirements.
- Read the Learning Path Operating Protocol and Button Transitions for current
  actions, progression, recovery, or UI actionability.
- Read Swift Architecture for current owners and dependencies.
- Read Episode Architecture Execution Plan for any episode/runtime migration,
  centralized semantic ingress, replay, simulation, UI state-machine, or
  `OperatorWorkspace` replacement task.
- Read Episode Architecture Vocabulary whenever target names, type boundaries,
  observation/evidence semantics, or forbidden synonyms matter.
- Read Current Evidence before any status or validation claim.
- Read the Attended Hardware Runbook before explicitly authorized physical work.
- A focused task normally needs the directly owning document, not every file.

## Single-plan rule

Do not check in temporary review reports, research comparisons, coordinator
prompts, rejected proposals, or competing architecture/execution plans.
Integrate an accepted change into the owning canonical document and delete the
source note. Git and Blackdog retain history.

The current Learning Path Mermaid and historical Current Evidence entries are
retained because their roles are explicit and noncompeting. Any new diagram
must live in its owning current or target document and must not offer another
architecture.
