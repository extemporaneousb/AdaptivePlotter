#!/bin/sh
set -eu

tag_name=adaptiveplotter-episode-baseline-v1

fail() {
    echo "episode baseline tag: $1" >&2
    exit 1
}

if [ "$#" -ne 2 ]; then
    fail "usage: $0 TASK-ID TESTED-BASELINE-COMMIT"
fi

task_id=$1
tested_commit=$2

case "$task_id" in
    TASK-*) task_suffix=${task_id#TASK-} ;;
    *) fail "invalid Blackdog task ID" ;;
esac
[ -n "$task_suffix" ] || fail "invalid Blackdog task ID"
case "$task_suffix" in
    *[!A-F0-9]*) fail "invalid Blackdog task ID" ;;
esac

if [ "${#tested_commit}" -ne 40 ]; then
    fail "tested commit must be a full 40-character object ID"
fi
case "$tested_commit" in
    *[!0-9a-f]*) fail "tested commit must be lowercase hexadecimal" ;;
esac

git cat-file -e "$tested_commit^{commit}" 2>/dev/null ||
    fail "tested commit is not a local commit"

project_root=$(git rev-parse --show-toplevel 2>/dev/null) ||
    fail "cannot resolve the current Git worktree"
blackdog="$project_root/.VE/bin/blackdog"
[ -x "$blackdog" ] || fail "repo-local Blackdog is unavailable"

valid_subject="AdaptivePlotter episode baseline; task=$task_id; tested=$tested_commit"
tag_ref="refs/tags/$tag_name"
peeled_ref="$tag_ref^{}"
validation_ref="refs/adaptiveplotter-tag-validation/$tag_name-$$"
tab=$(printf '\t')
remote_listing=$(mktemp -t adaptiveplotter-episode-tag.XXXXXX)
tag_object_listing=$(mktemp -t adaptiveplotter-episode-tag-object.XXXXXX)
task_show_listing=$(mktemp -t adaptiveplotter-episode-task-show.XXXXXX)

cleanup() {
    git update-ref -d "$validation_ref" >/dev/null 2>&1 || :
    rm -f "$remote_listing" "$tag_object_listing" "$task_show_listing"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

"$blackdog" task show --project-root "$project_root" --json > "$task_show_listing" ||
    fail "cannot inspect the current Blackdog task"
if ! python3 - "$task_show_listing" "$task_id" "$project_root" "$tested_commit" <<'PY'
import json
import re
import sys
from pathlib import Path


def reject(message: str) -> None:
    print(f"episode baseline tag task check: {message}", file=sys.stderr)
    raise SystemExit(1)


try:
    payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    show = payload["task_show"]
except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
    reject(f"invalid task-show result: {error}")

if show.get("task_id") != sys.argv[2]:
    reject("the supplied task ID is not the current Blackdog task")
if show.get("target_branch") != "main":
    reject("the current Blackdog target branch is not main")
if show.get("active_attempt") is not True or show.get("attempt_status") != "in_progress":
    reject("the current Blackdog task has no active in-progress attempt")
if show.get("execution_prompt_mode") != "skill":
    reject("the current Blackdog task was not started from the repo skill")
if Path(show.get("worktree_path", "")).resolve() != Path(sys.argv[3]).resolve():
    reject("Blackdog does not bind the task to this worktree")

lineage = show.get("resume_lineage")
if not isinstance(lineage, dict) or lineage.get("status") != "verified":
    reject("the Blackdog prompt replay lineage is not verified")
prompt_value = lineage.get("execution_prompt_file")
if not isinstance(prompt_value, str) or not prompt_value:
    reject("the verified execution prompt path is absent")
try:
    prompt_lines = Path(prompt_value).read_text(encoding="utf-8").splitlines()
except OSError as error:
    reject(f"the verified execution prompt is unreadable: {error}")
marker = "AdaptivePlotter episode WorkPackage: BASE-03"
if not prompt_lines or prompt_lines[0] != marker:
    reject("the verified execution prompt does not begin with the BASE-03 marker")
commit_marker = f"AdaptivePlotter tested baseline commit: {sys.argv[4]}"
if len(prompt_lines) < 2 or prompt_lines[1] != commit_marker:
    reject("the verified BASE-03 prompt does not bind the tested commit")

evidence_path = Path(sys.argv[3]) / "docs" / "CURRENT_EVIDENCE.md"
try:
    evidence = evidence_path.read_text(encoding="utf-8")
except OSError as error:
    reject(f"Current Evidence is unreadable: {error}")
evidence_commits = re.findall(
    r"^TESTED-BASELINE-COMMIT: ([0-9a-f]{40})$",
    evidence,
    re.MULTILINE,
)
if evidence_commits != [sys.argv[4]]:
    reject("Current Evidence does not uniquely bind the BASE-01 tested commit")
PY
then
    fail "current Blackdog task/package binding is invalid"
fi

verify_remote_main() {
    remote_main=$(git ls-remote --heads origin refs/heads/main) ||
        fail "cannot read origin/main"
    set -- $remote_main
    if [ "$#" -ne 2 ] || [ "$1" != "$tested_commit" ] || [ "$2" != refs/heads/main ]; then
        fail "origin/main does not equal the tested commit"
    fi
}

verify_remote_main

local_exists() {
    git show-ref --verify --quiet "$tag_ref"
}

verify_ref() {
    inspected_ref=$1
    inspected_label=$2
    object_type=$(git cat-file -t "$inspected_ref" 2>/dev/null) ||
        fail "$inspected_label object is unreadable"
    [ "$object_type" = tag ] || fail "$inspected_label is not annotated"

    git cat-file -p "$inspected_ref" > "$tag_object_listing" 2>/dev/null ||
        fail "$inspected_label content is unreadable"
    verified_object=$(git rev-parse "$inspected_ref" 2>/dev/null) ||
        fail "$inspected_label object ID is unreadable"
    validated_object=$(git mktag < "$tag_object_listing" 2>/dev/null) ||
        fail "$inspected_label object is malformed"
    [ "$validated_object" = "$verified_object" ] ||
        fail "validated tag content does not match the inspected object"
    direct_object=
    direct_type=
    internal_tag_name=
    while read -r header value remainder; do
        [ -n "$header" ] || break
        case "$header" in
            object)
                [ -z "$direct_object" ] || fail "$inspected_label repeats its object header"
                [ -z "${remainder:-}" ] || fail "$inspected_label has a malformed object header"
                direct_object=$value
                ;;
            type)
                [ -z "$direct_type" ] || fail "$inspected_label repeats its type header"
                [ -z "${remainder:-}" ] || fail "$inspected_label has a malformed type header"
                direct_type=$value
                ;;
            tag)
                [ -z "$internal_tag_name" ] || fail "$inspected_label repeats its tag header"
                [ -z "${remainder:-}" ] || fail "$inspected_label has a malformed tag header"
                internal_tag_name=$value
                ;;
        esac
    done < "$tag_object_listing"
    [ "$direct_object" = "$tested_commit" ] ||
        fail "$inspected_label does not directly target the tested commit"
    [ "$direct_type" = commit ] ||
        fail "$inspected_label does not directly target a commit"
    [ "$internal_tag_name" = "$tag_name" ] ||
        fail "$inspected_label name does not match the canonical tag"

    verified_peeled=$(git rev-parse "$inspected_ref^{}" 2>/dev/null) ||
        fail "$inspected_label cannot be peeled"
    [ "$verified_peeled" = "$tested_commit" ] ||
        fail "$inspected_label targets a different commit"

    verified_subject=$(git for-each-ref --format='%(contents:subject)' "$inspected_ref") ||
        fail "$inspected_label subject is unreadable"
    [ "$verified_subject" = "$valid_subject" ] ||
        fail "$inspected_label belongs to a different task or commit"
}

verify_local() {
    verify_ref "$tag_ref" "local tag"
    local_object=$verified_object
}

query_remote() {
    : > "$remote_listing"
    if git ls-remote --exit-code --tags origin "$tag_ref" "$peeled_ref" > "$remote_listing"; then
        remote_exists=1
    else
        query_status=$?
        if [ "$query_status" -eq 2 ]; then
            remote_exists=0
            return
        fi
        fail "cannot inspect the remote tag"
    fi

    remote_object=
    remote_peeled=
    while IFS="$tab" read -r object_id ref_name; do
        case "$ref_name" in
            "$tag_ref")
                [ -z "$remote_object" ] || fail "remote tag ref is duplicated"
                remote_object=$object_id
                ;;
            "$peeled_ref")
                [ -z "$remote_peeled" ] || fail "remote peeled tag ref is duplicated"
                remote_peeled=$object_id
                ;;
            *) fail "remote returned an unexpected tag ref" ;;
        esac
    done < "$remote_listing"

    [ -n "$remote_object" ] || fail "remote tag object is missing"
    [ -n "$remote_peeled" ] || fail "remote tag is lightweight or malformed"
    [ "$remote_peeled" = "$tested_commit" ] ||
        fail "remote tag targets a different commit"
}

query_remote

if [ "$remote_exists" -eq 1 ]; then
    advertised_remote_object=$remote_object
    if local_exists; then
        verify_local
        candidate_object=$local_object
    else
        git fetch --no-tags origin "$tag_ref:$validation_ref" ||
            fail "cannot fetch the remote tag for validation"
        verify_ref "$validation_ref" "remote tag candidate"
        candidate_object=$verified_object
        [ "$candidate_object" = "$advertised_remote_object" ] ||
            fail "validated remote tag object differs from the advertised object"
    fi
    [ "$candidate_object" = "$advertised_remote_object" ] ||
        fail "local and remote annotated tag objects disagree"
    query_remote
    [ "$remote_exists" -eq 1 ] || fail "remote tag disappeared during validation"
    [ "$remote_object" = "$advertised_remote_object" ] ||
        fail "remote tag changed during validation"
    [ "$candidate_object" = "$remote_object" ] ||
        fail "validated tag object differs from the final remote object"
else
    if local_exists; then
        verify_local
        publish_ref=$tag_ref
        publish_object=$local_object
    else
        tagger_identity=$(git var GIT_COMMITTER_IDENT 2>/dev/null) ||
            fail "cannot resolve the tagger identity"
        printf '%s\n' \
            "object $tested_commit" \
            "type commit" \
            "tag $tag_name" \
            "tagger $tagger_identity" \
            "" \
            "$valid_subject" > "$tag_object_listing"
        candidate_object=$(git mktag < "$tag_object_listing" 2>/dev/null) ||
            fail "cannot create the task-bound annotated tag object"
        git update-ref "$validation_ref" "$candidate_object" "" ||
            fail "cannot install the temporary tag candidate"
        verify_ref "$validation_ref" "new tag candidate"
        publish_ref=$validation_ref
        publish_object=$verified_object
    fi
    git push origin "$publish_ref:$tag_ref" ||
        fail "exact non-force tag push failed; rerun only this same Blackdog task"
    query_remote
    [ "$remote_exists" -eq 1 ] || fail "remote tag is absent after push"
    [ "$publish_object" = "$remote_object" ] ||
        fail "pushed remote tag object differs from the validated candidate"
    if local_exists; then
        verify_local
        [ "$local_object" = "$remote_object" ] ||
            fail "published local and remote tag objects disagree"
    fi
fi

verify_remote_main

echo "episode baseline tag published: $tag_name -> $tested_commit ($task_id)"
