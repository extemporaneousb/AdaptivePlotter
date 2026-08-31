---
name: run-multi-agent-wave
description: "Select and coordinate the next eligible AdaptivePlotter episode WorkPackage as one guarded multi-agent wave. Use when asked to run or continue the next migration wave, find unclaimed and unblocked episode work, resume recoverable package work, or request a bounded offload from an active episode coordinator."
---

# Run Multi-Agent Wave

Invoke as `$run-multi-agent-wave`.

Use this skill only for the episode migration governed by
`docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md`. `AGENTS.md` remains the Blackdog
lifecycle authority, `$adaptiveplotter` remains the package compiler/executor,
and the execution plan, vocabulary, and Current Evidence remain the substantive
authorities.

## Run the wave

1. From the normal primary workspace, consume the mode-0600 hash-bound launch
   capsule directly:

   ```sh
   ./.VE/bin/python Scripts/episode_wave_capsule.py consume
   ```

   If it is missing or stale, run `./.VE/bin/python
   Scripts/episode_wave_capsule.py create` and then consume it. The consumer
   revalidates canonical `main`, clean Git state, every bound authority hash,
   the complete ledger/evidence contract, and live repository-wide Blackdog
   claims. A stale capsule is discarded, never interpreted.
2. Use only the verified capsule's package-specific pointers for prompt
   compilation and coordination. For a tranche, every ordered authority slice
   includes its current-owner inventory and exact same-slice deletion-scan
   pointers; do not flatten those slices into one broad cutover. Do not reread
   the complete ledger, vocabulary, Current Evidence, or coordination protocol
   at startup. Mutable canonical documents remain authority; the capsule is only
   a validated read accelerator.
3. Resolve every live claim reported by the capsule before looking for new work.
   `terminal_history` is a visible hash-bound diagnostic, not a live claim: it
   can contain only fully cleaned terminal blocked/failed history whose exact
   replay binds a removed or currently dependency-ineligible package. Unknown
   replay identity, any owner/finalization residue, or a current dependency-ready
   recoverable ordinary package remains a live blocker.
   Fetch its current Blackdog `next_action`; never cache lifecycle actions in the
   capsule. Resume only verified
   recoverable `repository`, `software`, or `gate` work, or use the available
   task/thread messaging capability to request one bounded non-overlapping
   offload from its active coordinator. Never cancel, replace, or infer that a
   claim is stale.
4. With no claim, deterministically select the first eligible pending selectable
   `repository`, `software`, or `gate` row in canonical ledger order. An
   `authority-slice` is carried only by its named tranche and is never claimed
   individually. This
   invocation authorizes that selection. It does not authorize an
   `attended-physical` or `remote-git` package.
5. Apply `$adaptiveplotter execute episode package <ID>` to the selected ID and
   append the reference's coordination overlay to the complete compiled package
   prompt. Start exactly one Blackdog task. If the atomic reservation loses a
   race, return to claim resolution instead of selecting a different row.
6. Use at most four active agents total: this invoking coordinator plus no more
   than three workers or critics. Act only as coordinator: own lifecycle,
   bounded read-only inspection, delegation, acceptance, retasking, and landing.
   Do not implement, edit, or run validation yourself. Use fewer agents when
   work is not safely disjoint, and preserve a slot for the one fresh critic.
7. For a named tranche, run per-slice build, focused, affected-consumer, `DIFF`,
   and `DELETE` checks as each typed authority slice closes. At the tranche
   boundary, use at most one bounded fresh-context critic and run `QUICK`,
   `JOURNEY`, and `STRICT` once on the stable integrated candidate. Retask only
   red-line defects: compiler/test failure, duplicate effect-producing authority,
   unauthorized motion, a Stop/shutdown race that can start effects, automatic
   retry/redraw with possible ink, destructive persistence ordering, or fabricated
   evidence. Record other findings in Current Evidence without retasking. A
   docs-only evidence update with unchanged source and test hashes reruns only
   documentation and diff-hygiene gates. A red-line final-gate defect may receive
   a narrowly authorized repair and affected validation but never reopens
   criticism. Never commission a post-pass, fresh, confirmation, precautionary,
   or delta-recheck critic.
8. Require a serial documentation integrator in every wave. A tranche completion
   and successor capsule are valid only when its root and every slice completion
   row name the one same nonempty Blackdog task/landing. The same landing
   updates the execution-plan ledger row, Current Evidence gate table and detail,
   and every routed canonical document affected by the package, including current
   architecture when as-built topology or ownership changes. Record a reviewed
   no-change disposition for the remaining canonical documents. Stale
   documentation fails the wave.
9. Stop only at a typed Blackdog blocker, an exact unresolved dependency or
   authorization boundary, a declined/unavailable offload, or verified package
   landing on `main`. After Blackdog completion, verify the landed commit is
   current `main`, `git status --short` is empty, and no unfinished wave task or
   retained disposable worktree remains. Generate the successor capsule
   mechanically from that landed clean state. Do not dispatch a successor scout.
