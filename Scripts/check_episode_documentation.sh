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

rg -Fq 'use only for work outside the episode architecture and migration' \
    .codex/skills/adaptiveplotter/SKILL.md ||
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
.codex/skills/adaptiveplotter/SKILL.md
.codex/skills/adaptiveplotter/references/episode-migration.md'

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
    rg -Fq "$command" .codex/skills/adaptiveplotter/SKILL.md ||
        fail "skill is missing explicit command: $command"
done

if rg -n 'continue episode migration|first[[:space:]]+pending|select the first|unscoped.*execute' \
    .codex/skills/adaptiveplotter/SKILL.md \
    .codex/skills/adaptiveplotter/references/episode-migration.md; then
    fail "implicit package continuation remains"
fi

if rg -n 'Interactive learning complete|accepted model' \
    README.md \
    docs/ATTENDED_HARDWARE_RUNBOOK.md \
    docs/DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md \
    docs/PRODUCT_CONTRACT.md; then
    fail "obsolete or vague current operator terminology remains"
fi

rg -Fq 'source at DOC-01 violates that contract' README.md ||
    fail "README hides the current outside-applicability evidence defect"
rg -Fq 'Current source at DOC-01 violates that contract' \
    docs/DISCOVERY_AND_OBSERVED_TRIAL_PROTOCOL.md ||
    fail "operator protocol hides the current outside-applicability evidence defect"

if rg -n 'The current source contains exactly two post-Boundary|The current implementation exposes exactly two persistent global controls|The visible Learning Path ends at the one-Go 4\.1' docs/CURRENT_EVIDENCE.md; then
    fail "historical Current Evidence still claims obsolete behavior is current"
fi

if rg -n 'Drawing Boundary[[:space:]]+Boundary envelope' docs/SWIFT_ADAPTIVE_PLOTTER_ARCHITECTURE.md; then
    fail "malformed as-built Boundary wording remains"
fi

if rg -n '^\| (BASE-00|EA-10|EA-11) \|' docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md; then
    fail "superseded broad package row remains"
fi

sh -n Scripts/publish_episode_baseline_tag.sh ||
    fail "baseline tag publication procedure has invalid shell syntax"
sh Scripts/test_publish_episode_baseline_tag.sh ||
    fail "baseline tag publication recovery test failed"

echo "episode documentation contract passed"
