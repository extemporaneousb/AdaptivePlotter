# AGENTS

Keep repo-specific requirements outside the managed Blackdog section below.

## Repository episode workflow

For requests about episode architecture, migration, package execution, or the named
`$adaptiveplotter audit`, `compile`, and `execute` episode commands, read
[the repository episode workflow](.codex/guidance/adaptiveplotter-workflow.md).
Its authorization limits apply before the generated generic workflow: episode audit
and compile remain read-only, execution requires the named package or the explicitly
invoked wave selector, and neither authorizes attended-physical or remote-Git work.
Keep these repository-owned refinements outside the generated skill directory.

<!-- BLACKDOG MANAGED CONTRACT:BEGIN -->
## Blackdog Contract

This section is managed by `blackdog repo install` and `blackdog repo refresh`.
Keep repo-specific requirements outside this block.

- For ordinary or underspecified repository requests, automatically read the guidance catalog in `.codex/skills/adaptiveplotter/references/catalog.md` before choosing a method or composing a task. Select relevant guides from the actual request and context; do not require the user to name a skill or copy a prompt. Explicit constraints override defaults; quoted roles are not assignments, and analysis does not authorize implementation. Apply strong working conventions unless concrete evidence justifies a departure. The host owns interpretation and agent execution.
- Use the installed `blackdog` executable or the exact workspace executable returned by Blackdog; do not mutate control files by hand.
- `blackdog.toml` is the machine-readable source of truth for handler setup and routed docs.
- `task begin` is the one normal implementation entrypoint. Run it directly; it performs its own readiness checks and returns the branch-backed task workspace where implementation edits belong.
- `blackdog worktree preflight --project-root .` is explicit read-only diagnosis. It does not start work and is not a separate prerequisite for `task begin`.
- Implementation edits belong only in the `workspace role: task` workspace returned by `task begin`; analysis-only work may stay in the current checkout but must not leave implementation edits there.
- When `task begin` runs from a normal linked worktree, Blackdog treats that linked branch as the target branch and lands the task back there.
- Blackdog does not require `.VE/`. Explicit project environment handlers may create one; virtual environments are unversioned and bound to one worktree path, so never copy them.
- Before normal repo-skill implementation, create two mode-0600 UTF-8 temporary files outside the repo: `request_file` contains the exact triggering user request verbatim, and `execution_prompt_file` contains the composed goal, context, constraints, and done condition prompt. Set those shell variables to absolute paths and run the structured begin command below.
- Build `guidance_args` as a shell array of repeated `--guidance SELECTOR` pairs for the selected guides and repository refinements; select `engineering` and `evidence` for implementation plus relevant specializations. Build `execution_context_args` with only known `--host`, `--host-version`, `--model`, and `--reasoning-effort` values, or use an empty array when unknown. These are caller-declared context, not model selection controls.
- Normal repo-skill implementation uses `blackdog task begin --project-root . --actor codex --execution-prompt-file "$execution_prompt_file" --prompt-mode skill --request-file "$request_file" "${guidance_args[@]}" "${execution_context_args[@]}" --json`. `--actor` defaults to `codex`; the explicit value here makes ownership visible.
- Delete `request_file` and `execution_prompt_file` only when the structured `task begin` result contains both a nonempty `execution_prompt_replay_artifact_path` and a nonempty `user_prompt_replay_artifact_path`; otherwise preserve both temporary inputs.
- Before landing, set `completion_summary` to concise human-readable change statements: the first nonblank line becomes the Git subject and each later nonblank line is one major body item. Do not put Blackdog metadata in it. Build the `validation_args` shell array with at least one repeated `--validation` plus `NAME=passed|failed|skipped`; never submit placeholders or invented evidence.
- For new work, do not pass `--task`; `task begin` creates the task and returns its workspace. A machine-emitted retry may identify an existing task explicitly.
- Abandoned work is canceled by default; use `task reopen` only when the work should re-enter the normal queue.
- For every structured result from `task begin`, `task show`, `task recover`, `task cancel`, `task reopen`, `task land`, `task reconcile-landing`, `task close`, and `task cleanup`, treat its `next_action` as the sole authority regardless of `operation_status`: execute its exact `argv` when `kind=command`; choose only a complete action from `choices` or `alternatives`; stop when `kind=blocked` or `kind=complete`; never infer an action from display text, reason or error prose, or summaries.
- When repository policy enables automatic stale recovery, `task land` may internally run one exact task-worktree `git rebase --autostash`, execute the configured validation commands, and retry canonical landing. Trust the returned `next_action`: a commandless `automatic_stale_recovery_*` blocker is an exceptional handoff to the current landing agent. Preserve the retained task workspace, never choose ours/theirs, reset, force-update, or skip validation, and satisfy the typed `required_inputs` before retrying normal `task land`.
- If any task surface reports `next_action.action_id=retry_task_close_finalization`, execute that exact argv until close completes. Its hidden close-request guard and terminal evidence are machine-emitted replay capabilities; never omit, edit, or reconstruct them. A blocked action has no recovery command and requires evidence inspection.
- Do not launch an external browser, use macOS `open`, use `xdg-open`, or run headed Playwright/browser sessions for agent verification unless the user explicitly asks for a user-visible browser. Prefer Codex in-app browser tools or headless evidence.
- After `repo install`, `repo update`, or `repo refresh`, run `git status --short`; commit or land managed repo changes, or report the checkout as intentionally dirty before finishing.
- Before finishing implementation work, re-check branch and dirty state and do not leave uncommitted changes from your work.
- Treat the `target_branch` selected and recorded by Blackdog for the task as authoritative when landing and verifying the result; never assume it is `main` and never switch it manually.

Document routing catalog: read only the entries relevant to the current task; do not load every document by default:
- `docs/INDEX.md`

Run the narrowest relevant validation after changes. Repo defaults:
- `make docs-check`
- `make quick-test`
- `git diff --check`

<!-- BLACKDOG MANAGED CONTRACT:END -->
