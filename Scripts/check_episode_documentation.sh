#!/bin/sh
set -eu

fail() {
    echo "episode documentation contract: $1" >&2
    exit 1
}

canonical_docs='ATTENDED_HARDWARE_RUNBOOK.md
CURRENT_EVIDENCE.md
DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md
EPISODE_ARCHITECTURE_EXECUTION_PLAN.md
EPISODE_ARCHITECTURE_VOCABULARY.md
INDEX.md
LEARNING_PATH_BUTTON_TRANSITIONS.md
PRODUCT_CONTRACT.md
ROADMAP.md
SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md'

for name in $canonical_docs; do
    test -f "docs/$name" || fail "missing canonical docs/$name"
    rg -Fq "$name" docs/INDEX.md || fail "docs/INDEX.md does not inventory $name"
done

rg -Fq '.codex/guidance/adaptiveplotter-workflow.md' AGENTS.md ||
    fail "AGENTS.md does not route the repository episode refinement"

rg -Fq 'use only for work outside the episode architecture and migration' \
    .codex/guidance/adaptiveplotter-workflow.md ||
    fail "generic AdaptivePlotter path can bypass episode governance"

for path in docs/*.md; do
    name=${path##*/}
    if ! printf '%s\n' "$canonical_docs" | grep -Fxq "$name"; then
        fail "unrouted or competing document $path"
    fi
done

for term in \
    EpisodeGoal EpisodeDefinition EpisodeManifest EpisodeState PlotterIntent \
    IntentDecision IntentAvailability IntentReceipt EpisodeEvent PlotterEffect \
    EffectPermit EffectResult CapabilityFact StopCapability Observation \
    Measurement Evidence EpisodeOutcome Assessment EpisodeJournal EpisodeTrace \
    WorkPackage BlackdogTask PlotterIntentGateway PlotterOperationRegistry; do
    rg -Fq "\`$term\`" docs/EPISODE_ARCHITECTURE_VOCABULARY.md ||
        fail "canonical vocabulary is missing $term"
done

target_surfaces='docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md
.codex/guidance/adaptiveplotter-workflow.md
.codex/guidance/episode-migration.md
.codex/skills/run-multi-agent-wave/SKILL.md
.codex/skills/run-multi-agent-wave/references/wave-coordination.md'

if rg -n 'ActionDecision|ActionAvailability|ActionReceipt|SemanticActionAuthority|SemanticActionGateway|episode/action/effect|Action availability|Action receipt' $target_surfaces; then
    fail "forbidden target synonym remains"
fi

if rg -ni 'scheduled|scheduler|automation' $target_surfaces; then
    fail "task-orchestration design does not belong in the episode contract"
fi

for command in \
    '$adaptiveplotter audit episode migration' \
    '$adaptiveplotter compile episode package <ID>' \
    '$adaptiveplotter execute episode package <ID>'; do
    rg -Fq "$command" .codex/guidance/adaptiveplotter-workflow.md ||
        fail "skill is missing explicit command: $command"
done

rg -Fq '$run-multi-agent-wave' \
    .codex/skills/run-multi-agent-wave/SKILL.md ||
    fail "wave skill is missing its explicit invocation"

wave_protocol_normalized=$(tr '\n' ' ' < .codex/skills/run-multi-agent-wave/references/wave-coordination.md | tr -s '[:space:]' ' ')

for phrase in \
    'One wave is exactly one canonical' \
    'selectable work item executed in exactly one Blackdog task worktree.' \
    'tranche is that work item and carries its fixed ordered typed authority slices' \
    'Select the first eligible row.' \
    'No two live workers may' \
    'write the same file' \
    'Editing stops before validation begins.' \
    'at most one bounded' \
    'Retask only a red-line blocker' \
    'Never commission a post-pass, fresh, confirmation, precautionary, or delta-recheck critic.' \
    "execute episode package <ID>"; do
    printf '%s\n' "$wave_protocol_normalized" | rg -Fq "$phrase" ||
        fail "wave coordination contract is missing: $phrase"
done

if rg -n 'continue episode migration|first[[:space:]]+pending|unscoped.*execute|select the first[[:space:]]+pending' \
    $target_surfaces; then
    fail "unsafe implicit package continuation remains"
fi

if rg -n 'no automatic package selection|Never infer or auto-select|direct interactive request naming the package is required' \
    $target_surfaces; then
    fail "obsolete automatic-selection prohibition remains"
fi

if rg -n 'Interactive learning complete|accepted model' \
    README.md \
    docs/ATTENDED_HARDWARE_RUNBOOK.md \
    docs/DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md \
    docs/PRODUCT_CONTRACT.md; then
    fail "obsolete or vague current operator terminology remains"
fi

for path in README.md docs/DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md; do
    applicability_contract=$(tr '\n' ' ' < "$path" | tr -s '[:space:]' ' ')
    for phrase in \
        'An outside-applicability plan can execute but invokes no Vision' \
        'zero verified strokes as non-attributable'; do
        printf '%s\n' "$applicability_contract" | rg -Fq "$phrase" ||
            fail "$path omits the current outside-applicability evidence boundary: $phrase"
    done
    for historical_fix in DOC-01 FIX-01; do
        rg -Fq "$historical_fix" "$path" ||
            fail "$path omits the historical applicability correction $historical_fix"
    done
    if printf '%s\n' "$applicability_contract" | rg -Fq 'source at DOC-01 violates that contract'; then
        fail "$path presents the corrected DOC-01 applicability defect as current"
    fi
done
rg -Fq 'projectionOutsideTipApplicability' docs/DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md ||
    fail "operator protocol omits the exact outside-applicability non-attribution reason"

if rg -n 'The current source contains exactly two post-Boundary|The current implementation exposes exactly two persistent global controls|The visible Learning Path ends at the one-Go 4\.1' docs/CURRENT_EVIDENCE.md; then
    fail "historical Current Evidence still claims obsolete behavior is current"
fi

if rg -n 'Drawing Boundary[[:space:]]+Boundary envelope' docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md; then
    fail "malformed as-built Boundary wording remains"
fi

if rg -n '^\| (BASE-00|EA-10|EA-11) \|' docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md; then
    fail "superseded broad package row remains"
fi

echo "episode documentation contract passed"
