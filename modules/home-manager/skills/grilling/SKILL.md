---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round, providing your recommended answer for each question. Then wait for the user's answers before the next round.

## Asking questions

**Always use OpenCode's built-in `question` tool to ask the user questions.** Do not ask questions through regular assistant messages.

For each round, make a single `question` tool call containing all questions in the current frontier.

For each question:

- Provide a short, descriptive `header`.
- Write a clear, specific `question` explaining the decision.
- Provide meaningful `options` with concise labels and descriptions.
- Put your recommended answer first and append "(Recommended)" to its label.
- Explain relevant trade-offs in the option descriptions.
- Allow the user to choose a different option or provide a custom answer.
- Use `multiple: true` only when the decision genuinely allows multiple selections.

Frame questions so that selecting the recommended option is equivalent to accepting your recommendation. Do not force yes/no questions when concrete alternatives would communicate the decision more clearly.

When a question is genuinely open-ended, use the tool's custom-answer capability rather than inventing arbitrary choices.

**Never substitute a Markdown-formatted questionnaire for the `question` tool.** If the tool is unavailable, explain the limitation and ask through the available interface.

## Advancing the design tree

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them.

After receiving the `question` tool's results:

1. Record the decisions the user made.
2. Identify which dependencies have been resolved.
3. Recompute the frontier.
4. Ask the next frontier using the `question` tool.

A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Do not assume the user accepted your recommendation unless their answer explicitly indicates that.

## Researching facts

Finding _facts_ is your job, never the user's.

When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent with a fresh context window to find it; don't ask the user for anything you could look up yourself.

Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report. Ask the rest of the frontier now using the `question` tool.

The _decisions_ are the user's: put each to them and wait.

## Completion

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed.

Do not act on the plan until the user confirms you have reached a shared understanding.

Use the `question` tool to request this final confirmation, with options to:

- Confirm the shared understanding and finish grilling.
- Revisit decisions or explore remaining concerns.

If the user wants to revisit anything, update the design tree and continue grilling.
