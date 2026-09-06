# Pair Codex Setup

Complete, safety-first setup for async AI pair programming with Codex.

It installs global handoff access plus an optional isolated Codex profile with
pairing instructions, selected skills, pinned plugins, and the public
[Pair Codex Handoffs](https://github.com/grimmely/pair-codex-handoffs) tool.
Your transcripts, session bundles, and patches stay in a private GitHub
repository that you choose during installation.

## Before installation

Install and authenticate these prerequisites:

- Bash, Fish 4+, Git, `curl`, and `tar` with gzip support.
- Node.js 22+ and `codex-session-exporter` on `PATH`.
- Codex CLI, signed in: `codex login status`.
- GitHub CLI, signed in: `gh auth status --hostname github.com`.

Then create a private GitHub repository for your pair’s handoff storage,
initialized on `main`:

```text
OWNER/PRIVATE-HANDOFF-STORAGE
```

It must:

- Be private.
- Use `main` as its default branch.
- Be accessible to `gh repo view OWNER/PRIVATE-HANDOFF-STORAGE`.
- Grant your pair collaborator write access before you share a handoff URL.

The installer never creates this repository. Handoff contents are plaintext in
Git; compression reduces size but does not encrypt data.

## Install

```fish
curl -fsSL https://raw.githubusercontent.com/grimmely/pair-codex-setup/main/bootstrap.sh | bash
```

The bootstrapper clones the complete setup bundle into a private temporary
directory, runs its bundled installer, then removes that temporary checkout.
Run it from an interactive terminal: installer asks for your storage repository.

Or inspect and run a local checkout:

```fish
git clone https://github.com/grimmely/pair-codex-setup.git
cd pair-codex-setup
bash install.sh
```

When prompted, enter the private storage repository in `owner/repo` form.
Installation validates private visibility and `main`, then stages all files and
publishes them only after plugins and storage setup succeed.

```text
$HOME/.pair-codex/
  tools/pair-codex-handoffs/      public Fish tool + handoff skill source
  handoff/storage-repo            chosen GitHub storage slug
  handoff-storage/OWNER/REPO/     private local storage checkout
  AGENTS.md, config.toml, agents/ pairing environment

$HOME/.agents/skills/
  handoff/                        Codex handoff skill
  grilling/, to-tickets/, unslop/ pairing skills
```

### Upgrade a previous Pair Codex install

From an updated checkout, run `bash install.sh` again. It recognizes the
unmodified generated layouts from the first two setup releases and the earlier
async-handoff release. It adds the new tool and private storage configuration,
then updates only the known generated `PAIRING.md`.

Existing generic global skills and the former `$HOME/pair-codex-handoffs`
checkout remain untouched. After the new `handoff` skill publishes, the old
`async-pair-handoff` skill moves to
`$HOME/.pair-codex/legacy-skills/async-pair-handoff`; its files remain
available, but Codex no longer discovers its unsafe obsolete command. This
move happens only for the exact unmodified legacy skill; otherwise installation
stops for manual reconciliation. Use `$handoff` after upgrading. Do not run
the former checkout’s scripts.

An installer stops if a managed Codex file, the new handoff destination, or an
existing `handoff` skill differs from what it recognizes. Reconcile that state
manually or use a fresh `--codex-home`; it never merges or replaces it.

Start Codex normally for daily handoffs:

```fish
codex
```

`$handoff` is globally available. With no `CODEX_HOME`, it sends and receives
sessions from your normal `$HOME/.codex` store while using handoff configuration
and private storage under `$HOME/.pair-codex`.

Use the isolated Pair Codex profile only when you also want its local pairing
instructions, hooks, and plugins:

```fish
CODEX_HOME="$HOME/.pair-codex" codex
```

## Daily handoff flow

In Codex, choose `handoff` from the slash-command list or type `$handoff`.
Use `$handoff help` for a short, non-mutating command menu.

```text
end of day
  -> $handoff send
  -> inspect pending source/session details
  -> confirm export + private Git push
  -> share returned GitHub URL

next session
  -> $handoff receive <shared URL>
  -> inspect context and patch
  -> confirm session import
  -> continue work
```

The skill asks for confirmation immediately before cloning storage, importing a
session, committing, or pushing. It never checks out a sender commit or applies
a source patch automatically.

## Change storage later

Ask Codex for `$handoff configure`, or use the dispatcher directly:

```fish
fish "$HOME/.pair-codex/tools/pair-codex-handoffs/scripts/pair-handoff.fish" \
  configure --storage-repo OWNER/ANOTHER-PRIVATE-STORAGE
```

Changing storage creates or reuses that repository’s own local checkout. It
does not replace or delete previous storage checkouts.

Check health and currently supported harnesses:

```fish
fish "$HOME/.pair-codex/tools/pair-codex-handoffs/scripts/pair-handoff.fish" \
  status
```

Only Codex is supported today. Storage is already organized for additional
harness adapters:

```text
handoffs/codex/YYYY-MM-DD/<handoff-id>/
```

## What gets installed

The setup includes the pairing contract, focused agent roles, a session-start
reminder, and pinned plugins. It does not copy login state, credentials,
histories, caches, trusted-project state, worktrees, or hook approvals.

Included skills:

- `handoff`: guided private async handoffs.
- `grilling`: one material design challenge before implementation.
- `to-tickets`: feedback-first work slices.
- `unslop`: concise, natural responses.

## Safety and updates

- Existing Codex state or global skills are never replaced, except an explicit
  `sync-handoff-skill.fish` refresh of `handoff`, which first saves a backup.
- A recognized prior generated `PAIRING.md` is the one upgrade exception.
- The installer refuses symbolic-link destinations.
- Storage requires a private GitHub repo, SSH/HTTPS remote, and `main`.
- Bundles above 100 MiB are refused; Git history retains prior bundles.
- Review patches with `git apply --check` before applying them.
- The installer clones and executes the public handoff tool's `main`; inspect
  that repository before installing if you need to audit executable sources.

Update the setup repository and public tool independently on `main`:

```fish
git pull --ff-only
git -C "$HOME/.pair-codex/tools/pair-codex-handoffs" pull --ff-only
fish "$HOME/.pair-codex/tools/pair-codex-handoffs/scripts/sync-handoff-skill.fish"
```

The skill refresh is explicit and preserves its previous copy under
`$HOME/.pair-codex/handoff-skill-backups/`.

For full handoff command documentation, see
[Pair Codex Handoffs](https://github.com/grimmely/pair-codex-handoffs).
