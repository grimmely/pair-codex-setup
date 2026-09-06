# Pairing feedback loop

This setup keeps AI pairing steerable. A ticket names an outcome; each turn
produces one fact that can change the next move.

## Working rhythm

```text
investigate -> show fact
test        -> show red
minimal code -> show green
```

Pause only after evidence that can change a decision, scope, or next action.
Continue routine validation automatically.

`continue` authorizes one next evidence-producing step. Any other reply may
redirect the work.

## Where behavior lives

| Location | Responsibility |
| --- | --- |
| `AGENTS.md` | Pairing contract and implementation rhythm |
| `hooks/feedback-learning.sh` | Short session-start pairing reminder |
| `../.agents/skills/async-pair-handoff/SKILL.md` | Confirmed async handoffs |
| `../.agents/skills/to-tickets/SKILL.md` | Feedback-first ticket drafting |
| `config.toml` | Local hook registration and plugin setting |

The former `learning-output-style` plugin is disabled. Its cached hook trust
record was removed. The local hook provides the replacement behavior.

## Ticket rule

```text
ticket        = user-visible outcome
feedback step = one observed signal
```

For ordinary work, start with one question, smallest action, evidence, and
stop point. For a wide refactor, first map callers and compatibility
constraints; decide whether expand-contract is needed only after that fact.

## Teaching behavior

Keep teaching brief and specific to current code. Explain a decision when it
helps. Do not turn normal configuration or obvious work into learner exercises.

## Trust note

No project-trust records ship in this bundle. Choose trust per project on the
receiving computer.
