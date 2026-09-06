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
git clone --branch v1.0.0 --depth 1 \
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
