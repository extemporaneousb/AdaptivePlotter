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
   compilation and coordination. Do not reread the complete ledger, vocabulary,
   Current Evidence, or coordination protocol at startup. Mutable canonical
   documents remain authority; the capsule is only a validated read accelerator.
3. Resolve every live claim reported by the capsule before looking for new work.
   Fetch its current Blackdog `next_action`; never cache lifecycle actions in the
   capsule. Resume only verified
   recoverable `repository`, `software`, or `gate` work, or use the available
   task/thread messaging capability to request one bounded non-overlapping
   offload from its active coordinator. Never cancel, replace, or infer that a
   claim is stale.
4. With no claim, deterministically select the first eligible pending
   `repository`, `software`, or `gate` row in canonical ledger order. This
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
   work is not safely disjoint, and preserve a slot for the fresh critic.
7. Require a serial documentation integrator in every wave. The same landing
   updates the execution-plan ledger row, Current Evidence gate table and detail,
   and every routed canonical document affected by the package, including current
   architecture when as-built topology or ownership changes. Record a reviewed
   no-change disposition for the remaining canonical documents. Stale
   documentation fails the wave.
8. Stop only at a typed Blackdog blocker, an exact unresolved dependency or
   authorization boundary, a declined/unavailable offload, or verified package
   landing on `main`. After Blackdog completion, verify the landed commit is
   current `main`, `git status --short` is empty, and no unfinished wave task or
   retained disposable worktree remains. Generate the successor capsule
   mechanically from that landed clean state. Do not dispatch a successor scout.
