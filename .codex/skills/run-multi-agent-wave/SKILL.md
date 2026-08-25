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

1. Read the [AdaptivePlotter skill](../adaptiveplotter/SKILL.md), its focused
   [episode-migration protocol](../adaptiveplotter/references/episode-migration.md), and
   [references/wave-coordination.md](references/wave-coordination.md)
   completely before selecting or coordinating work.
2. Reconcile canonical Git, repository-wide Blackdog state, the complete work
   ledger, required gates, and Current Evidence exactly as the reference
   requires.
3. Resolve an existing claim before looking for new work. Resume only verified
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
6. Act only as coordinator: own lifecycle, bounded read-only inspection,
   delegation, acceptance, retasking, and landing. Do not implement, edit, or
   run validation yourself. Require workers and the fresh critic to use the
   concise status contract in the reference.
7. Stop only at a typed Blackdog blocker, an exact unresolved dependency or
   authorization boundary, a declined/unavailable offload, or verified package
   landing. Do not describe an ineligible row as runnable work.
