---
name: to-tickets
description: Break a plan, spec, or the current conversation into a set of tracer-bullet tickets, each declaring its blocking edges, published to the configured tracker (edges as text in one file per ticket locally, or native blocking links on a real tracker).
---

# To Tickets

Break a plan, spec, or conversation into **tickets**. Each ticket names a
tracer-bullet outcome, its blocking edges, and its first feedback step.

Discover the project's issue tracker and label vocabulary from `AGENTS.md`,
repository documentation, remotes, and available tools. If no tracker is
configured, use local files. Do not create external issues unless the user
requested publication or approved it.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a reference (a spec path, an issue number or URL) as an argument, fetch it and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

Note likely prefactors as candidates. Make identifying one the first feedback
step; do not sequence it yet.

### 3. Draft feedback-first tickets

Break the work into **tracer bullet** tickets. A ticket names a user-visible
outcome. It is not a unit of uninterrupted work.

<feedback-first-rules>

- A ticket's outcome cuts a narrow but COMPLETE path through applicable layers.
- Its first feedback step changes only one thing: investigate -> show fact;
  test -> show red; or minimal code -> show green.
- State the question, smallest action, evidence to show, and stop point.
- Stop after that evidence. Plan no later step until it exists.
- If a prefactor seems useful, establish its need as the first feedback step.

</feedback-first-rules>

Give each ticket its **blocking edges**: the other tickets that must complete before it can start. A ticket with no blockers can start immediately.

**Wide refactors need a smaller first feedback step.** For a mechanical change
with a large blast radius, first map the affected callers and compatibility
constraints. Show that fact, then decide whether an expand–contract sequence
is necessary. Do not pre-plan its batches before that evidence.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each ticket, show:

- **Title**: short descriptive name
- **Blocked by**: which other tickets (if any) must complete first
- **What it delivers**: the end-to-end behaviour this ticket makes work
- **First feedback**: question, smallest action, evidence, and stop point

Ask only the highest-impact question, then wait for the answer. Start with:

- Does this breakdown need a split, merge, or blocker correction?

Iterate until the user approves the breakdown.

### 5. Publish the tickets to the configured tracker

Publish the approved tickets using the configured tracker. The tickets are the
same either way; only the shape of blocking edges changes:

- **Local files** → write one file per ticket under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order (blockers first). Each file's "Blocked by" lists the numbers/titles it depends on. Use the per-ticket file template below: one ticket per file, never a single combined file.
- **A real issue tracker (GitHub, Linear, …)** → when authorized, publish one
  issue per ticket in dependency order (blockers first) so each ticket's
  blocking edges can reference real identifiers. Use the platform's native
  blocking or sub-issue relationship where it has one; otherwise set each
  ticket's "Blocked by" to the blocking issues. Apply `ready-for-agent` only
  when the repository uses that label.

Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain that means top to bottom.

Do NOT close or modify any parent issue.

<local-ticket-template>

# <NN>: <Ticket title>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective, not a layer-by-layer implementation list.

**Blocked by:** the numbers/titles of the tickets that gate this one, or "None (can start immediately)".

**First feedback:** <question> -> <smallest action> -> <evidence to show>.
Stop after this evidence.

**Status:** ready-for-agent

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2

</local-ticket-template>

<issue-template>

## Parent

A reference to the parent issue on the tracker (if the source was an existing issue, otherwise omit this section).

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective, not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## First feedback

<Question> -> <smallest action> -> <evidence to show>. Stop after this evidence.

## Blocked by

- A reference to each blocking ticket, or "None (can start immediately)".

</issue-template>

In either form, avoid specific file paths or code snippets: they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it and note briefly that it came from a prototype. Trim to the decision-rich parts, not a working demo, just the important bits.
