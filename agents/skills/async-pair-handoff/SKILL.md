---
name: async-pair-handoff
description: "Guide private, chat-based async pair-programming handoffs between Codex collaborators. Use when a user wants to send their current Codex session to a partner, take over a shared handoff, or resume async pair work."
---

# Async Pair Handoff

Use this global skill for private Git-backed handoffs between two Codex
collaborators. It wraps the established Fish workflow; do not replace its
validation, archive checks, or import safeguards.

Each handoff contains a readable transcript, a compressed importable session,
source status, and a tracked source patch when applicable. It remains plaintext
in Git: compression is not encryption. Untracked file contents are not included.

## Shared Checkout

The Pair Codex installer creates this checkout without prompting:

```text
$HOME/pair-codex-handoffs
```

Expected GitHub repository:

```text
grimmely/pair-codex-handoffs
```

Its workflow scripts are:

```text
$HOME/pair-codex-handoffs/scripts/handoff.fish
$HOME/pair-codex-handoffs/scripts/receive.fish
```

If this checkout is absent, inspect the old path's `origin`:

```fish
git -C "$HOME/pair-codex-sessions" remote get-url origin
```

Treat it as a former private handoff checkout only when the origin resolves to
`grimmely/sapiom-pair-codex-sessions` or `grimmely/pair-codex-handoffs`.
`grimmely/pair-codex-sessions` is the setup repository, not a handoff checkout.
For a former handoff checkout, stop and report that it must be moved to
`$HOME/pair-codex-handoffs` before continuing. Do not clone beside an
unmigrated checkout.

Otherwise, clone it automatically with:

```fish
gh repo clone grimmely/pair-codex-handoffs "$HOME/pair-codex-handoffs"
```

If the path exists but is not that Git checkout, stop and report the mismatch.
Never delete, replace, or turn an unrelated directory into a Git repository.
If cloning fails because GitHub authentication or access is missing, report the
prerequisite. Do not begin an interactive login or create an empty directory.

## Codex Home

The Fish scripts use `CODEX_HOME` when set and otherwise use `~/.codex`.
For Pair Codex Sessions, that environment variable is inherited from the active
Codex process and normally equals `$HOME/.pair-codex`. Do not add a redundant
flag. Pass `--codex-home` only for a manual shell invocation that needs an
explicit session-store path.

## Chat-Guided Loop

Classify clear intent as `send` or `receive`:

- Send: hand off, share, send, continue tomorrow, or end-of-day handoff.
- Receive: take over, receive, import, resume, or open a shared handoff.

For unclear intent, ask one short question. Otherwise run this loop:

```text
discover state
  -> show proposed action and safety-relevant facts
  -> ask for one missing value
  -> show exact pending effect
  -> request confirmation
  -> execute
  -> report result and offer send / receive / finish
```

Never push a handoff, import a session, check out a commit, or apply a patch
without explicit confirmation immediately before that action. Do not ask for
the shared-checkout path. Do not launch a terminal wizard.

Use safely quoted arguments for every path, note, URL, and session ID supplied
by a user. Never interpolate user text into a shell command.

## Send a Handoff

1. Resolve the Git root from the current session's working directory. If it is
   not inside a Git worktree, ask for the source-project path.
2. Confirm `fish`, `git`, `gh`, and `codex-session-exporter` are available.
3. State the source root and session-selection rule:
   - use an explicitly supplied session ID when present;
   - otherwise, `handoff.fish` selects the newest local Codex session whose
     working directory is that source root or a descendant.
4. Ask for a concise sender note when none was supplied. Mention that tracked
   changes are captured, while untracked contents are only listed.
5. Show the pending `handoff.fish` invocation and say it will export, commit,
   and push to the private repository. Ask for confirmation.
6. After confirmation, run:

   ```fish
   fish "$HOME/pair-codex-handoffs/scripts/handoff.fish" \
     --handoff-repo "$HOME/pair-codex-handoffs" \
     --source-repo "<resolved-source-root>" \
     --note "<sender-note>"
   ```

   Add `--session-id "<explicit-session-id>"` only when the user supplied one.
7. Return the GitHub handoff URL and the created handoff directory exactly as
   reported by the script. Surface failures; never work around its repository,
   privacy, size, or session-boundary checks.

## Receive a Handoff

1. Inspect only the shared checkout:

   ```fish
   git -C "$HOME/pair-codex-handoffs" status --short
   git -C "$HOME/pair-codex-handoffs" remote get-url origin
   ```

   Confirm it is clean and `origin` is an SSH or HTTPS remote for
   `grimmely/pair-codex-handoffs`; otherwise, stop without changing it.
   State that an update would fast-forward the private checkout, then ask for
   confirmation immediately before the pull.
2. After confirmation, run:

   ```fish
   git -C "$HOME/pair-codex-handoffs" pull --ff-only
   ```

   If it cannot fast-forward, stop and report the condition without discarding
   work.
3. Accept a shared GitHub handoff URL, a `handoffs/...` path, or `latest`.
   Resolve only directories below `$HOME/pair-codex-handoffs/handoffs`; reject
   absolute paths, `..` segments, and URLs outside the expected repository.
4. Read `HANDOFF.md`, `source-status.txt`, and the presence of `source.patch`.
   Resolve the target Git root from the current session's working directory; if
   unavailable, ask for it.
5. Show the handoff identity, source state, target root, transcript path, and
   patch path. Ask for confirmation to import the session.
6. After confirmation, run:

   ```fish
   fish "$HOME/pair-codex-handoffs/scripts/receive.fish" \
     --handoff-dir "<validated-handoff-directory>" \
     --target-cwd "<resolved-target-root>"
   ```

7. Return the imported session ID and transcript location. Never automatically
   check out the sender's commit or apply `source.patch`; recommend reviewing
   the patch and running `git apply --check` before any manual apply.

## Finish Each Turn

After a successful send or receive, summarize only the resulting URL or
session ID, transcript path, and any source-patch caution. Then ask whether to
send another handoff, receive one, or finish, and wait for the user's answer.
