---
name: zed-pr-review
description: Open a GitHub pull request in Zed's diff view using an isolated checkout and the PR's actual base branch. Use when the user asks to open, inspect, or review a PR in Zed, including guided reviews and requests without an explicit skill invocation.
---

# Review a PR in Zed

Open the requested PR's current changes in Zed, ready for the user to review.
Prefer Zed's native worktree and branch controls. Use CLI support when native
controls are unavailable or cannot select the exact PR revision.

## Resolve the comparison

- Resolve the PR URL or number from the request or current conversation.
  Ask only if the target remains ambiguous.
- Read repository-specific instructions before checkout operations.
- Obtain current PR metadata through an available GitHub connector or `gh`:
  repository, title, state, head repository/branch/SHA, base branch/SHA, and
  changed-file list. Do not assume the base is `main`; stacked PRs often target
  another feature branch. For example:
  `gh pr view <PR> --repo <owner/repo> --json title,url,state,headRefName,headRefOid,baseRefName,baseRefOid,isCrossRepository,headRepository,headRepositoryOwner,files`
- Find the matching local repository and verify its remote. Inspect existing
  worktrees and their status. Never reset, stash, or switch a dirty checkout as
  part of opening a review. Preserve running development services.

## Open through Zed

Use the available native-app automation tool, following its initialization and
interaction instructions. Inspect UI state after each meaningful transition;
opening a window and typing into a file chooser must be separate verified steps.

1. Open the matching project in Zed. Through the command palette (`Cmd+Shift+P`
   on macOS), run `git: fetch` to refresh remote references.
2. Reuse a clean, dedicated checkout already at the requested head SHA when
   possible. Otherwise run `git: worktree`, create a separate worktree, and
   switch to it. Use `git: checkout branch` to select the PR's head branch there.
   Verify the resulting checkout's HEAD matches the PR metadata before review.
3. Run `git: compare with branch`. Select the PR's actual base reference,
   typically `origin/<baseRefName>` when origin is the base repository. Do not
   substitute Zed's default comparison branch.
4. Confirm that the diff opened, its base is correct, and its files correspond
   to the PR. A clean worktree with an empty ordinary `git: diff` is not proof
   that the PR has no changes: the review needs the branch comparison.
5. Keep the PR comparison tab active and show the Outline Panel. If hidden,
   run `outline panel: toggle focus` (`Cmd+Shift+B` on macOS). If already visible,
   leave it open rather than blindly toggling it. Verify its file tree lists
   the active diff's files, not the whole project or a single file's symbols.
   Leave the diff and Outline Panel visible together for navigation.

Use current official documentation if commands differ in the installed version:
https://zed.dev/docs/git, https://zed.dev/docs/all-actions, and
https://zed.dev/docs/outline-panel.

## Fallbacks and comparison pitfalls

- If Zed cannot prepare the exact head (including fork PRs or a branch already
  checked out elsewhere), use Git to fetch the PR head into a dedicated review
  ref and create an isolated detached worktree. Verify the fetched SHA. Open
  that directory in Zed, then use its native comparison command.
- Locate the installed Zed CLI rather than assuming it is on PATH. On macOS,
  the app may provide `/Applications/Zed.app/Contents/MacOS/cli`. Inspect help
  before choosing flags; use a new window when preserving an existing project.
- GitHub PR comparisons use the merge base. Rewritten or unmerged base branches
  can make earlier slices appear again. Compare the displayed scope with the
  current GitHub changed-file list and check ancestry when they disagree.
  Explain inherited changes; do not silently rebase, merge, or change the PR
  target to make the diff smaller. A direct base-to-head comparison is a
  different view and must be identified as such if explicitly requested.
- If app automation is unavailable, give the shortest verified native steps
  and report what could not be opened. Do not claim visual verification.

## Finish at the review boundary

Report the PR, checkout location, comparison base, and any scope discrepancy.
When the user wants guided review, open the first relevant changed file and
explain one small block at a time. Opening a diff does not authorize code edits,
commits, pushes, GitHub comments, approvals, or merges.

Automatic skill selection should remain enabled. A request such as
"open PR 123 in Zed" should select this workflow without requiring `$zed-pr-review`.
