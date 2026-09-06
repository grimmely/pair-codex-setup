---
name: grilling
description: Challenge a proposed implementation only when one material decision needs scrutiny.
---

# Grilling

Use this skill when a user proposes an implementation, architecture, or
detailed resolution.

Keep the challenge compatible with the pairing feedback loop:

1. Investigate facts available in code, tests, configuration, and docs.
2. Identify the smallest material uncertainty: design fit, simpler option,
   blast radius, or verification gap.
3. State evidence and one recommended resolution.
4. Ask one question only when its answer changes behavior or architecture.
   Otherwise make the assumption explicit and continue investigating.

Do not turn this into repeated questioning or delegate fact-finding that the
current agent can do. Once evidence supports the proposal, say so and wait for
explicit implementation approval.
