# Pair Codex Setup

Portable, safety-first Codex pairing setup.

It recreates the pairing contract, agent roles, feedback hook, and three
behavior-critical skills. It never exports login state, connector credentials,
histories, caches, project trust, worktrees, or hook approvals.

## Install

Requirements:

- macOS or Linux with Bash.
- Git, to clone this repository.
- Codex CLI and sign-in only for `--with-plugins`.

Use a released tag rather than a mutable branch when one is available:

```bash
git clone --branch v1.0.1 --depth 1 \
  https://github.com/grimmely/pair-codex-setup.git
cd pair-codex-setup
bash install.sh
```

Default install is core-only. It makes no network request and does not invoke
the Codex CLI.

```text
Codex state  $HOME/.pair-codex
User skills  $HOME/.agents/skills
```

Start it:

```bash
CODEX_HOME="$HOME/.pair-codex" codex
```

Then run `/hooks`, inspect `feedback-learning.sh`, and explicitly trust it.
The installer never uses `--dangerously-bypass-hook-trust`.

## How to pair with AI

This setup keeps the human in control through short, observable loops. Do not
ask it to disappear for twenty minutes and return with a large change. Ask for
one fact, one failing check, or one smallest passing change at a time.

### The core loop

```text
goal or problem
  -> alignment: inspect relevant code and show facts
  -> approval: "implement" or "let's do it"
  -> one feedback-producing step
       investigate -> show fact
       test        -> show red
       minimal code -> show green
  -> report evidence
  -> decide: continue, redirect, or stop
```

The agent continues routine checks when evidence cannot change the next move.
It pauses when a decision, scope change, or architecture choice needs you.

### Your controls

| Say | Expected behavior |
| --- | --- |
| Describe a goal, bug, or question | Alignment. Agent investigates only. |
| `implement` or `let's do it` | Approves the discussed change. |
| `continue` | Exactly one next evidence-producing step. |
| Correct scope or priority | Redirects the next step. |
| `stop` or `hold here` | Ends active work. |

`continue` is deliberately small. It preserves a point where you can change
direction before work grows expensive to revise.

### Shape a useful slice

```text
slice
  outcome       = observable user or system behavior
  first feedback = one fact, red test, or green change
  evidence      = command output, diff, test result, or screenshot
  stop point    = evidence that can change the next decision
  next step     = chosen only after seeing that evidence
```

Good:

```text
Investigate why an expired invite still opens. Show the request path and test.
```

```text
Implement rejection of expired invites. First add the smallest failing test.
```

Too broad:

```text
Rework the whole invitation system and make it robust.
```

For broad work, first ask for the map: callers, boundaries, compatibility
constraints, and the smallest end-to-end outcome. Use `/to-tickets` when a
plan needs separate feedback-first slices.

### Why show red?

A red test shows the requested behavior is observable and missing before code
changes. Green then means the smallest change made that observation pass.

```text
expected behavior
  -> test fails for the right reason
  -> minimal code
  -> same test passes
  -> refactor while green
```

Do not force a red test for research, documentation, or changes where a test
does not improve confidence. The point is evidence, not ceremony.

### Prompt patterns

```text
Investigate <problem>. Show facts only; do not edit yet.

Implement <outcome>. First establish the narrowest failing test.

Continue.

Redirect: keep <constraint>; do not change <boundary>.

Stop here. Summarize evidence and remaining risk.
```

Keep teaching brief and attached to the current code or decision. Ask for an
explanation when it helps, not an exercise for routine work.

### Where the behavior comes from

```text
README.md
  -> human operating guide
codex/AGENTS.md
  -> alignment, approval, quality, and response contract
codex/PAIRING.md
  -> feedback-loop rule and ticket shape
codex/hooks/feedback-learning.sh
  -> short session-start reminder
agents/skills/to-tickets
  -> feedback-first ticket drafting
```

Read [AGENTS.md](codex/AGENTS.md) for the full contract and
[PAIRING.md](codex/PAIRING.md) for the concise operating rule.

## Optional plugins

Third-party plugins are explicit opt-in. The installer pins the Claude
marketplace to a Git commit, stages the whole install, then publishes it only
after every plugin succeeds.

```bash
bash install.sh --with-plugins
```

If plugin installation fails, retry after fixing the cause. No Codex state or
skills were published by that failed run.

`plugins/host-managed-plugins.txt` records source-machine desktop/runtime
plugins. It does not install them: their marketplaces are version-specific.

## Safety model

- Refuses an existing or symbolic-link Codex destination.
- Creates new Codex and skill directories with owner-only permissions.
- Never replaces an existing global skill.
- Uses Codex's supported global skill path: `$HOME/.agents/skills`.
- Resolves an installer symlink back to this bundle before reading files.
- Excludes the `chief-of-staff` agent and broad automation skills. They can
  archive messages, change calendars, collect tool data, or depend on another
  runtime.

Included skills:

- `grilling`: design challenge when a proposed implementation needs scrutiny.
- `to-tickets`: feedback-first slices.
- `unslop`: concise, natural writing.

See `skills-manifest.txt` for exact scope.

Agent roles install as instructions, never as binaries or MCP servers.
`docs-lookup` uses Context7 when `--with-plugins` installs it, then falls back
to the tools available in the receiving runtime. `e2e-runner` uses only an
already installed project runner. Language-specific roles require that
project's normal toolchain.

See `agents-manifest.txt` for the conditional roles.

## Verify

```bash
bash tests/install-test.sh
CODEX_HOME="$HOME/.pair-codex" codex doctor
```

Codex discovers global skills at `$HOME/.agents/skills`. Hooks need local
review and trust on the receiving computer.
