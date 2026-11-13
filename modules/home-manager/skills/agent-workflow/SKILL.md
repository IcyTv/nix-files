---
name: agent-workflow
description: Plan and coordinate multi-step implementations, resolve roadblocks, and preserve context across compaction. Main agents load before multi-step work; delegates load only when their assigned task needs these details.
---

# Agent workflow

## Planning and approval

The main agent owns the overall plan, user questions, and approval. Before a
multi-step implementation, investigate likely roadblocks and create a detailed
todo list. Present the plan for approval before changing code. Use the grilling
skill when implementing features or making unresolved design decisions.

Delegate only bounded tasks covered by the approved plan. Include acceptance
conditions, relevant paths, constraints, and verification commands. Delegates
must not repeat the overall planning or approval process, expand scope, or
delegate again. Report blockers and decisions to the main agent instead.

The main agent checks delegate evidence before declaring completion. Run focused
tests and review the new changes. Distinguish observed results from assumptions,
and report any verification that could not run.

## Roadblocks

1. Search the web for existing solutions and useful terminology. Prefer primary
   documentation and relevant upstream issues.
2. Read the relevant local code and dependencies. Prefer glob and grep tools;
   use binary inspection tools only when source is insufficient.
3. If still blocked, ask the user. Explain the failure, research, evidence, and
   remaining options. Link relevant issues where possible.

Delegates return unresolved blockers to the main agent, which owns user questions.
Do not bypass safety restrictions to make progress.

## Compaction

Preserve the active goal, approved decisions, constraints, changed files,
verification evidence, blockers, and next steps. Keep finished work brief.

For detailed completed work, write a uniquely named Markdown note under
`/tmp/opencode/` and retain its path in the compacted context. Keep assistant-only
notes out of project history. Never discard user work to make context smaller.
