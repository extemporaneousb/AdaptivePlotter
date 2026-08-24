#!/bin/sh
set -eu

fail() {
    echo "episode baseline tag test: $1" >&2
    exit 1
}

repository_root=$(pwd)
publisher="$repository_root/Scripts/publish_episode_baseline_tag.sh"
fixture_root=$(mktemp -d -t adaptiveplotter-tag-test.XXXXXX)
trap 'rm -rf "$fixture_root"' EXIT HUP INT TERM
remote="$fixture_root/remote.git"
work="$fixture_root/work"
tag_name=adaptiveplotter-episode-baseline-v1
task_prompt="$fixture_root/execution-prompt.txt"
task_show="$fixture_root/task-show.json"

write_task_context() {
    current_task=$1
    current_target=$2
    current_package=$3
    current_commit=$4
    printf '%s\n' \
        "AdaptivePlotter episode WorkPackage: $current_package" \
        "AdaptivePlotter tested baseline commit: $current_commit" \
        > "$task_prompt"
    printf '%s\n' \
        "{\"task_show\":{\"task_id\":\"$current_task\",\"target_branch\":\"$current_target\",\"active_attempt\":true,\"attempt_status\":\"in_progress\",\"execution_prompt_mode\":\"skill\",\"worktree_path\":\"$work\",\"resume_lineage\":{\"status\":\"verified\",\"execution_prompt_file\":\"$task_prompt\"}}}" \
        > "$task_show"
}

assert_no_local_ref() {
    if git show-ref --verify --quiet "refs/tags/$tag_name"; then
        fail "publisher installed a previously absent canonical local tag"
    fi
    validation_refs=$(git for-each-ref --format='%(refname)' refs/adaptiveplotter-tag-validation)
    [ -z "$validation_refs" ] || fail "publisher left a validation ref"
}

git init --bare --quiet "$remote"
git init --quiet -b main "$work"
git -C "$work" config user.name "AdaptivePlotter Contract Test"
git -C "$work" config user.email "adaptiveplotter-contract@example.invalid"
mkdir -p "$work/.VE/bin"
printf '%s\n' \
    '#!/bin/sh' \
    '[ "$#" -eq 5 ] || exit 2' \
    '[ "$1" = task ] || exit 2' \
    '[ "$2" = show ] || exit 2' \
    '[ "$3" = --project-root ] || exit 2' \
    '[ "$5" = --json ] || exit 2' \
    "exec /bin/cat '$task_show'" \
    > "$work/.VE/bin/blackdog"
chmod 700 "$work/.VE/bin/blackdog"
printf '%s\n' baseline > "$work/baseline.txt"
git -C "$work" add baseline.txt
git -C "$work" commit --quiet -m "Create baseline fixture"
tested_commit=$(git -C "$work" rev-parse HEAD)
mkdir -p "$work/docs"
printf 'TESTED-BASELINE-COMMIT: %s\n' "$tested_commit" > "$work/docs/CURRENT_EVIDENCE.md"
write_task_context TASK-A1 main BASE-03 "$tested_commit"
git -C "$work" remote add origin "$remote"
git -C "$work" push --quiet origin main

(
    cd "$work"

    sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1 || fail "initial tag publication failed"
    assert_no_local_ref
    sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1 || fail "remote-present retry failed"
    assert_no_local_ref

    git fetch --quiet --no-tags origin "refs/tags/$tag_name:refs/tags/$tag_name"
    sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1 || fail "local-and-remote retry failed"

    git --git-dir="$remote" update-ref -d "refs/tags/$tag_name"
    sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1 || fail "local-only recovery failed"

    if sh "$publisher" TASK-B2 "$tested_commit" >/dev/null 2>&1; then
        fail "a different task adopted the existing tag"
    fi

    printf '%s\n' \
        'AdaptivePlotter episode WorkPackage: EA-01' \
        'AdaptivePlotter episode WorkPackage: BASE-03' \
        "AdaptivePlotter tested baseline commit: $tested_commit" \
        > "$task_prompt"
    if sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1; then
        fail "an embedded BASE-03 marker bypassed a different package"
    fi
    write_task_context TASK-A1 main BASE-03 0000000000000000000000000000000000000000
    if sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1; then
        fail "a prompt bound to a different tested commit published the tag"
    fi
    write_task_context TASK-A1 main BASE-03 "$tested_commit"
    printf 'TESTED-BASELINE-COMMIT: %s\n' 0000000000000000000000000000000000000000 \
        > docs/CURRENT_EVIDENCE.md
    if sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1; then
        fail "a commit absent from BASE-01 Current Evidence published the tag"
    fi
    printf 'TESTED-BASELINE-COMMIT: %s\n' "$tested_commit" > docs/CURRENT_EVIDENCE.md
    write_task_context TASK-A1 topic BASE-03 "$tested_commit"
    if sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1; then
        fail "a non-main Blackdog target published the tag"
    fi
    write_task_context TASK-A1 main BASE-03 "$tested_commit"

    remote_peeled=$(git ls-remote --tags origin "refs/tags/$tag_name^{}" | awk '{print $1}')
    [ "$remote_peeled" = "$tested_commit" ] || fail "remote tag does not peel to the tested commit"

    inner_tag_object=$(git rev-parse "refs/tags/$tag_name")
    valid_subject="AdaptivePlotter episode baseline; task=TASK-A1; tested=$tested_commit"
    printf '%s\n' \
        "object $inner_tag_object" \
        "type tag" \
        "tag $tag_name" \
        "tagger AdaptivePlotter Contract Test <adaptiveplotter-contract@example.invalid> 1700000000 +0000" \
        "" \
        "$valid_subject" > "$fixture_root/nested-tag.txt"
    nested_tag_object=$(git mktag < "$fixture_root/nested-tag.txt")
    git push --quiet --force origin "$nested_tag_object:refs/tags/$tag_name"
    git tag -d "$tag_name" >/dev/null
    if sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1; then
        fail "a tag-of-tag was accepted as a direct commit tag"
    fi
    assert_no_local_ref

    printf '%s\n' \
        "object $tested_commit" \
        "type commit" \
        "tag $tag_name" \
        "" \
        "$valid_subject" > "$fixture_root/missing-tagger-tag.txt"
    malformed_tag_object=$(git hash-object --literally -t tag -w --stdin < "$fixture_root/missing-tagger-tag.txt")
    git push --quiet --force origin "$malformed_tag_object:refs/tags/$tag_name"
    if sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1; then
        fail "an annotated tag without a tagger header was accepted"
    fi
    assert_no_local_ref

    printf '%s\n' \
        "object $tested_commit" \
        "type commit" \
        "tag adversarial-internal-name" \
        "tagger AdaptivePlotter Contract Test <adaptiveplotter-contract@example.invalid> 1700000000 +0000" \
        "" \
        "$valid_subject" > "$fixture_root/wrong-internal-name-tag.txt"
    wrong_name_tag_object=$(git mktag < "$fixture_root/wrong-internal-name-tag.txt")
    git push --quiet --force origin "$wrong_name_tag_object:refs/tags/$tag_name"
    if sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1; then
        fail "an annotated tag with the wrong internal name was accepted"
    fi
    assert_no_local_ref

    race_subject="AdaptivePlotter episode baseline; task=TASK-RACE; tested=$tested_commit"
    printf '%s\n' \
        "object $tested_commit" \
        "type commit" \
        "tag $tag_name" \
        "tagger AdaptivePlotter Contract Test <adaptiveplotter-contract@example.invalid> 1700000000 +0000" \
        "" \
        "$race_subject" > "$fixture_root/race-tag.txt"
    race_tag_object=$(git mktag < "$fixture_root/race-tag.txt")
    remote_race_object=$(
        git --git-dir="$remote" hash-object -w -t tag --stdin < "$fixture_root/race-tag.txt"
    )
    [ "$remote_race_object" = "$race_tag_object" ] || fail "race object transfer failed"

    git --git-dir="$remote" update-ref "refs/tags/$tag_name" "$inner_tag_object"
    printf '%s\n' \
        '#!/bin/sh' \
        '[ "$1" = prepared ] || exit 0' \
        "git --git-dir='$remote' update-ref 'refs/tags/$tag_name' '$race_tag_object'" \
        > .git/hooks/reference-transaction
    chmod 700 .git/hooks/reference-transaction
    if sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1; then
        fail "a remote-present validation race was accepted"
    fi
    rm -f .git/hooks/reference-transaction
    assert_no_local_ref
    observed_race_object=$(git ls-remote --tags origin "refs/tags/$tag_name" | awk '{print $1}')
    [ "$observed_race_object" = "$race_tag_object" ] ||
        fail "publisher hid the remote-present validation race"

    git --git-dir="$remote" update-ref "refs/tags/$tag_name" "$inner_tag_object"
    printf '%s\n' race-main > race-main.txt
    git add race-main.txt
    git commit --quiet -m "Create origin main race fixture"
    raced_main_commit=$(git rev-parse HEAD)
    git push --quiet origin "$raced_main_commit:refs/heads/race-seed"
    git --git-dir="$remote" update-ref -d refs/heads/race-seed
    printf '%s\n' \
        '#!/bin/sh' \
        '[ "$1" = prepared ] || exit 0' \
        "git --git-dir='$remote' update-ref refs/heads/main '$raced_main_commit'" \
        > .git/hooks/reference-transaction
    chmod 700 .git/hooks/reference-transaction
    if sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1; then
        fail "an origin/main validation race was accepted"
    fi
    rm -f .git/hooks/reference-transaction
    assert_no_local_ref
    observed_main=$(git ls-remote --heads origin refs/heads/main | awk '{print $1}')
    [ "$observed_main" = "$raced_main_commit" ] ||
        fail "publisher hid the origin/main validation race"
    git --git-dir="$remote" update-ref refs/heads/main "$tested_commit"

    git --git-dir="$remote" update-ref -d "refs/tags/$tag_name"
    printf '%s\n' \
        '#!/bin/sh' \
        "git --git-dir='$remote' update-ref 'refs/tags/$tag_name' '$race_tag_object'" \
        > .git/hooks/pre-push
    chmod 700 .git/hooks/pre-push
    if sh "$publisher" TASK-A1 "$tested_commit" >/dev/null 2>&1; then
        fail "a conflicting remote race was accepted"
    fi
    rm -f .git/hooks/pre-push
    assert_no_local_ref
    observed_race_object=$(git ls-remote --tags origin "refs/tags/$tag_name" | awk '{print $1}')
    [ "$observed_race_object" = "$race_tag_object" ] ||
        fail "production publisher mutated the raced remote tag"
    observed_main=$(git ls-remote --heads origin refs/heads/main | awk '{print $1}')
    [ "$observed_main" = "$tested_commit" ] || fail "tag publication mutated origin/main"
)

echo "episode baseline tag publication test passed"
