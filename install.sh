#!/usr/bin/env bash

set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage: bash install.sh [options]

Install the complete Pair Codex setup without replacing existing state.

Options:
  --codex-home DIR  Destination for isolated Codex state.
                     Default: $HOME/.pair-codex
  --help            Show this message.
EOF
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    die "required command is not installed: $1"
}

require_fish_4() {
  local fish_version
  fish_version=$(fish --version 2>/dev/null) ||
    die 'Fish 4 or newer is required'

  if [[ ! "$fish_version" =~ ([0-9]+)\. ]]; then
    die "could not determine Fish version: $fish_version"
  fi
  if [ "${BASH_REMATCH[1]}" -lt 4 ]; then
    die "Fish 4 or newer is required; found: $fish_version"
  fi
}

require_node_22() {
  local node_version
  node_version=$(node --version 2>/dev/null) ||
    die 'Node 22 or newer is required'

  if [[ ! "$node_version" =~ ^v?([0-9]+)(\.|$) ]]; then
    die "could not determine Node version: $node_version"
  fi
  if [ "${BASH_REMATCH[1]}" -lt 22 ]; then
    die "Node 22 or newer is required; found: $node_version"
  fi
}

require_tar_gzip() {
  local tar_probe_dir
  tar_probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/pair-codex-tar.XXXXXX") ||
    die 'could not create a temporary tar capability check'
  : > "$tar_probe_dir/probe"
  if ! tar -C "$tar_probe_dir" -czf "$tar_probe_dir/probe.tar.gz" probe >/dev/null 2>&1; then
    rm -rf "$tar_probe_dir"
    die 'tar with gzip support is required'
  fi
  if ! tar -tzf "$tar_probe_dir/probe.tar.gz" >/dev/null 2>&1; then
    rm -rf "$tar_probe_dir"
    die 'tar with gzip support is required'
  fi
  rm -rf "$tar_probe_dir"
}

github_slug_from_remote() {
  local remote_url remote_slug
  remote_url=$1
  remote_slug=$remote_url

  case "$remote_slug" in
    git@github.com:*) remote_slug=${remote_slug#git@github.com:} ;;
    ssh://git@github.com/*) remote_slug=${remote_slug#ssh://git@github.com/} ;;
    https://github.com/*) remote_slug=${remote_slug#https://github.com/} ;;
    https://*@github.com/*) remote_slug=${remote_slug#*github.com/} ;;
    *) return 1 ;;
  esac

  remote_slug=${remote_slug%.git}
  [[ "$remote_slug" =~ ^[^/]+/[^/]+$ ]] || return 1
  printf '%s\n' "$remote_slug"
}

validate_tool_checkout() {
  local checkout_path checkout_root checkout_remote checkout_slug
  local required_path tool_branch
  checkout_path=$1
  [ ! -L "$checkout_path" ] ||
    die "handoff tool checkout must not be a symbolic link: $checkout_path"
  [ -d "$checkout_path" ] ||
    die "handoff tool checkout is not a directory: $checkout_path"

  checkout_root=$(git -C "$checkout_path" rev-parse --show-toplevel 2>/dev/null) ||
    die "handoff tool checkout is not a Git repository: $checkout_path"
  checkout_root=$(CDPATH='' cd -P -- "$checkout_root" && pwd) ||
    die "cannot resolve handoff tool checkout: $checkout_path"
  checkout_path=$(CDPATH='' cd -P -- "$checkout_path" && pwd) ||
    die "cannot resolve handoff tool checkout: $checkout_path"
  [ "$checkout_root" = "$checkout_path" ] ||
    die "handoff tool checkout must be its Git repository root: $checkout_path"

  checkout_remote=$(git -C "$checkout_path" remote get-url origin 2>/dev/null) ||
    die "handoff tool checkout has no origin remote: $checkout_path"
  checkout_slug=$(github_slug_from_remote "$checkout_remote") ||
    die "handoff tool checkout origin must use SSH or HTTPS for GitHub: $checkout_path"
  [ "$checkout_slug" = "$expected_tool_repo" ] ||
    die "handoff tool checkout origin must be: $expected_tool_repo"

  tool_branch=$(git -C "$checkout_path" branch --show-current) ||
    die "handoff tool checkout must use main: $checkout_path"
  [ "$tool_branch" = main ] ||
    die "handoff tool checkout must use main: $checkout_path"

  for required_path in \
    scripts/pair-handoff.fish \
    scripts/sync-handoff-skill.fish \
    scripts/handoff.fish \
    scripts/receive.fish \
    skills/handoff/SKILL.md \
    skills/handoff/agents/openai.yaml; do
    [ -f "$checkout_path/$required_path" ] ||
      die "handoff tool checkout is missing: $required_path"
  done
}

require_complete_environment() {
  local required_command
  for required_command in codex fish git tar gh node codex-session-exporter; do
    require_command "$required_command"
  done

  require_fish_4
  require_node_22
  require_tar_gzip
  codex login status >/dev/null 2>&1 ||
    die 'Codex CLI must be signed in before installation'
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    die 'GitHub CLI must be authenticated for github.com before installation'
  codex-session-exporter --help >/dev/null 2>&1 ||
    die 'codex-session-exporter with usable Node 22+ is required'
}

validate_storage_repo() {
  local storage_repo repository_metadata private_visibility default_branch push_permission
  storage_repo=$1
  [[ "$storage_repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
    die 'storage repository must use the form owner/repo'

  repository_metadata=$(gh api --hostname github.com "repos/$storage_repo" \
    --jq '[.private, (.default_branch // ""), (.permissions.push // false)] | @tsv' 2>/dev/null) ||
    die "cannot access storage repository through gh: $storage_repo"
  IFS=$'\t' read -r private_visibility default_branch push_permission <<< "$repository_metadata"
  [ "$private_visibility" = true ] ||
    die "storage repository must be private: $storage_repo"
  [ "$default_branch" = main ] ||
    die "storage repository must use main as its default branch: $storage_repo"
  [ "$push_permission" = true ] ||
    die "storage repository must grant you push access: $storage_repo"
}

prompt_storage_repo() {
  printf '%s\n' 'Create a private handoff storage repository first; it must use main and be accessible through gh.' >&2
  printf '%s' 'Private handoff storage repository (owner/repo): ' >&2
  IFS= read -r storage_repo || die 'could not read storage repository'
  validate_storage_repo "$storage_repo"
}

resolve_script_dir() {
  script_path=${BASH_SOURCE[0]}

  while [ -h "$script_path" ]; do
    script_parent=$(CDPATH='' cd -P -- "$(dirname -- "$script_path")" && pwd) ||
      die "cannot resolve installer path: $script_path"
    link_target=$(readlink "$script_path") ||
      die "cannot read installer symlink: $script_path"

    case "$link_target" in
      /*) script_path=$link_target ;;
      *) script_path=$script_parent/$link_target ;;
    esac
  done

  CDPATH='' cd -P -- "$(dirname -- "$script_path")" && pwd
}

validate_new_destination() {
  destination=$1
  label=$2

  [ -n "$destination" ] || die "$label destination is empty"
  [ ! -L "$destination" ] ||
    die "$label destination must not be a symbolic link: $destination"
  [ ! -e "$destination" ] ||
    die "$label destination already exists: $destination"

  destination_parent=$(dirname -- "$destination")
  destination_leaf=$(basename -- "$destination")
  case "$destination_leaf" in
    ''|.|..) die "$label destination must name a new directory" ;;
  esac

  [ -d "$destination_parent" ] ||
    die "$label destination parent does not exist: $destination_parent"
  [ -w "$destination_parent" ] ||
    die "$label destination parent is not writable: $destination_parent"

  destination_parent=$(CDPATH='' cd -P -- "$destination_parent" && pwd) ||
    die "cannot resolve $label destination parent: $destination_parent"
  validated_destination=$destination_parent/$destination_leaf
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    return 1
  fi
}

legacy_async_skill_is_generated() {
  local skill_path skill_hash metadata_hash entry_count
  skill_path=$1

  [ ! -L "$skill_path" ] && [ -d "$skill_path" ] || return 1
  [ ! -L "$skill_path/SKILL.md" ] && [ -f "$skill_path/SKILL.md" ] || return 1
  [ ! -L "$skill_path/agents" ] && [ -d "$skill_path/agents" ] || return 1
  [ ! -L "$skill_path/agents/openai.yaml" ] && [ -f "$skill_path/agents/openai.yaml" ] || return 1
  entry_count=$(find "$skill_path" -mindepth 1 -maxdepth 2 -print | wc -l | tr -d ' ')
  [ "$entry_count" = 3 ] || return 1

  skill_hash=$(sha256_file "$skill_path/SKILL.md") || return 1
  metadata_hash=$(sha256_file "$skill_path/agents/openai.yaml") || return 1
  [ "$skill_hash" = 09f9621d1f6b5de336a449332bb58d26f482c762f2b03840623c7135f098c34b ] &&
    [ "$metadata_hash" = e5d706028628824474d63b25f26a49c2bac0217f148b8e829176d9ba62c66fb3 ]
}

validate_existing_codex_home() {
  local destination destination_parent managed_file
  destination=$1

  [ -n "$destination" ] || die 'Codex destination is empty'
  [ ! -L "$destination" ] ||
    die "Codex destination must not be a symbolic link: $destination"
  [ -d "$destination" ] ||
    die "Codex destination is not a directory: $destination"

  destination_parent=$(dirname -- "$destination")
  [ -d "$destination_parent" ] ||
    die "Codex destination parent does not exist: $destination_parent"
  [ -w "$destination_parent" ] ||
    die "Codex destination parent is not writable: $destination_parent"
  destination_parent=$(CDPATH='' cd -P -- "$destination_parent" && pwd) ||
    die "cannot resolve Codex destination parent: $destination_parent"
  destination=$destination_parent/$(basename -- "$destination")

  for managed_file in AGENTS.md config.toml hooks/feedback-learning.sh; do
    [ ! -L "$destination/$managed_file" ] ||
      die "existing Pair Codex file must not be a symbolic link: $destination/$managed_file"
    cmp -s "$destination/$managed_file" "$script_dir/codex/$managed_file" ||
      die "existing Pair Codex file is modified; install into a new --codex-home instead: $destination/$managed_file"
  done
  [ ! -L "$destination/agents" ] ||
    die "existing Pair Codex agents must not be a symbolic link: $destination/agents"
  [ -d "$destination/agents" ] ||
    die "existing Pair Codex agents are missing: $destination/agents"
  diff -qr "$destination/agents" "$script_dir/codex/agents" >/dev/null ||
    die "existing Pair Codex agents are modified; install into a new --codex-home instead"

  [ ! -L "$destination/PAIRING.md" ] ||
    die "existing Pair Codex pairing guide must not be a symbolic link: $destination/PAIRING.md"
  if cmp -s "$destination/PAIRING.md" "$script_dir/codex/PAIRING.md"; then
    codex_pairing_needs_update=false
  elif sed '\|../\.agents/skills/handoff/SKILL\.md|d' "$script_dir/codex/PAIRING.md" |
      cmp -s - "$destination/PAIRING.md"; then
    codex_pairing_needs_update=true
  elif sed 's|../\.agents/skills/handoff/SKILL\.md|../.agents/skills/async-pair-handoff/SKILL.md|' \
      "$script_dir/codex/PAIRING.md" | cmp -s - "$destination/PAIRING.md"; then
    codex_pairing_needs_update=true
  else
    die "existing Pair Codex pairing guide is modified; install into a new --codex-home instead"
  fi

  [ ! -L "$destination/tools" ] ||
    die "existing Pair Codex tools directory must not be a symbolic link: $destination/tools"
  [ ! -e "$destination/tools" ] || [ -d "$destination/tools" ] ||
    die "existing Pair Codex tools path is not a directory: $destination/tools"
  [ ! -L "$destination/legacy-skills" ] ||
    die "existing Pair Codex legacy skills directory must not be a symbolic link: $destination/legacy-skills"
  [ ! -e "$destination/legacy-skills" ] || [ -d "$destination/legacy-skills" ] ||
    die "existing Pair Codex legacy skills path is not a directory: $destination/legacy-skills"
  for managed_path in \
    tools/pair-codex-handoffs \
    handoff \
    handoff-storage \
    legacy-skills/async-pair-handoff; do
    [ ! -e "$destination/$managed_path" ] && [ ! -L "$destination/$managed_path" ] ||
      die "existing Pair Codex handoff state needs manual reconciliation: $destination/$managed_path"
  done

  validated_destination=$destination
}

script_dir=$(resolve_script_dir)
codex_home="$HOME/.pair-codex"
expected_tool_repo='grimmely/pair-codex-handoffs'

while [ "$#" -gt 0 ]; do
  case "$1" in
    --codex-home)
      [ "$#" -ge 2 ] || die '--codex-home requires a directory'
      codex_home=$2
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

for required in \
  "$script_dir/codex/AGENTS.md" \
  "$script_dir/codex/PAIRING.md" \
  "$script_dir/codex/config.toml" \
  "$script_dir/codex/hooks/feedback-learning.sh" \
  "$script_dir/codex/agents" \
  "$script_dir/agents/skills" \
  "$script_dir/plugins/marketplaces.tsv" \
  "$script_dir/plugins/plugins.txt"; do
  [ -e "$required" ] || die "bundle is incomplete: $required"
done

codex_upgrade=false
codex_pairing_needs_update=false
if [ -e "$codex_home" ] || [ -L "$codex_home" ]; then
  validate_existing_codex_home "$codex_home"
  codex_upgrade=true
else
  validate_new_destination "$codex_home" 'Codex'
fi
codex_home=$validated_destination
codex_parent=$(dirname -- "$codex_home")

require_complete_environment
prompt_storage_repo

agents_home="$HOME/.agents"
agents_skills_home="$agents_home/skills"
agents_parent=$(dirname -- "$agents_home")

[ ! -L "$agents_home" ] ||
  die "global skills parent must not be a symbolic link: $agents_home"
[ ! -L "$agents_skills_home" ] ||
  die "global skills destination must not be a symbolic link: $agents_skills_home"
[ ! -e "$agents_home" ] || [ -d "$agents_home" ] ||
  die "global skills parent is not a directory: $agents_home"
[ ! -e "$agents_skills_home" ] || [ -d "$agents_skills_home" ] ||
  die "global skills destination is not a directory: $agents_skills_home"
[ -d "$agents_parent" ] ||
  die "global skills parent does not exist: $agents_parent"
[ -w "$agents_parent" ] ||
  die "global skills parent is not writable: $agents_parent"
if [ -e "$agents_home" ] && [ ! -e "$agents_skills_home" ]; then
  [ -w "$agents_home" ] ||
    die "global skills parent is not writable: $agents_home"
fi
if [ -e "$agents_skills_home" ]; then
  [ -w "$agents_skills_home" ] ||
    die "global skills destination is not writable: $agents_skills_home"
fi

legacy_async_skill_path=$agents_skills_home/async-pair-handoff
legacy_async_skill_present=false
if [ "$codex_upgrade" = true ] && { [ -e "$legacy_async_skill_path" ] || [ -L "$legacy_async_skill_path" ]; }; then
  [ ! -L "$legacy_async_skill_path" ] && [ -d "$legacy_async_skill_path" ] ||
    die "legacy async handoff skill must be a real directory: $legacy_async_skill_path"
  legacy_async_skill_is_generated "$legacy_async_skill_path" ||
    die "legacy async handoff skill differs; reconcile it manually: $legacy_async_skill_path"
  legacy_async_skill_present=true
fi

skills_to_publish=()
for source_skill in "$script_dir"/agents/skills/*; do
  [ -d "$source_skill" ] || die "invalid skill in bundle: $source_skill"
  skill_name=${source_skill##*/}
  if [ -e "$agents_skills_home/$skill_name" ] || \
     [ -L "$agents_skills_home/$skill_name" ]; then
    printf '%s\n' "Preserving existing global skill: $skill_name" >&2
  else
    skills_to_publish+=("$skill_name")
  fi
done

codex_stage=$(mktemp -d "$codex_parent/.pair-codex-stage.XXXXXX") ||
  die 'cannot create Codex staging directory'
agents_stage=$(mktemp -d "$agents_parent/.pair-codex-skills-stage.XXXXXX") ||
  die 'cannot create skills staging directory'
tool_stage=$codex_stage/tools/pair-codex-handoffs

transaction_marker='.pair-codex-install-marker'
transaction_id=${codex_stage##*/}
publish_started=false
codex_published=false
created_agents_home=false
created_skills_home=false
published_skills=()
upgrade_published_paths=()
upgrade_tools_parent_created=false
upgrade_pairing_backup=''
upgrade_pairing_backed_up=false
legacy_async_skill_destination=$codex_home/legacy-skills/async-pair-handoff
legacy_async_skill_retired=false
legacy_skills_parent_created=false

marker_matches() {
  marker_file=$1/$transaction_marker
  marker_value=''
  [ -f "$marker_file" ] || return 1
  IFS= read -r marker_value < "$marker_file" || return 1
  [ "$marker_value" = "$transaction_id" ]
}

move_staged_contents() (
  shopt -s dotglob nullglob
  staged_contents=("$1"/*)
  [ "${#staged_contents[@]}" -gt 0 ] || exit 1
  mv "${staged_contents[@]}" "$2"
)

mark_empty_destination() {
  local destination marker_file
  destination=$1
  marker_file=$destination/$transaction_marker

  if ! printf '%s\n' "$transaction_id" > "$marker_file"; then
    rm -f "$marker_file" 2>/dev/null || true
    rmdir "$destination" 2>/dev/null || true
    return 1
  fi
}

publish_upgrade_directory() {
  local staged_directory destination label
  staged_directory=$1
  destination=$2
  label=$3

  [ ! -e "$destination" ] && [ ! -L "$destination" ] ||
    die "$label appeared during install and was not replaced: $destination"
  mkdir "$destination" ||
    die "could not create $label destination: $destination"
  mark_empty_destination "$destination" ||
    die "could not mark $label destination: $destination"
  upgrade_published_paths+=("$destination")
  move_staged_contents "$staged_directory" "$destination" ||
    die "could not publish staged $label"
}

publish_upgrade_codex_state() {
  local tools_parent
  tools_parent=$codex_home/tools
  if [ ! -e "$tools_parent" ]; then
    mkdir "$tools_parent" ||
      die "could not create Pair Codex tools directory: $tools_parent"
    upgrade_tools_parent_created=true
  fi
  [ ! -L "$tools_parent" ] && [ -d "$tools_parent" ] ||
    die "Pair Codex tools directory is unsafe: $tools_parent"

  publish_upgrade_directory "$tool_stage" "$tools_parent/pair-codex-handoffs" 'handoff tool'
  publish_upgrade_directory "$codex_stage/handoff" "$codex_home/handoff" 'handoff configuration'
  publish_upgrade_directory "$codex_stage/handoff-storage" "$codex_home/handoff-storage" 'handoff storage'

  if [ "$codex_pairing_needs_update" = true ]; then
    upgrade_pairing_backup=$codex_stage/PAIRING.md.pre-handoff-migration
    cp "$codex_home/PAIRING.md" "$upgrade_pairing_backup" ||
      die 'could not preserve the previous Pair Codex pairing guide'
    upgrade_pairing_backed_up=true
    mv -f "$codex_stage/PAIRING.md" "$codex_home/PAIRING.md" ||
      die 'could not update the Pair Codex pairing guide'
  fi
}

retire_legacy_async_skill() {
  local legacy_skills_parent
  [ "$legacy_async_skill_present" = true ] || return 0

  legacy_skills_parent=$codex_home/legacy-skills
  if [ ! -e "$legacy_skills_parent" ]; then
    mkdir "$legacy_skills_parent" ||
      die "could not create legacy skills directory: $legacy_skills_parent"
    legacy_skills_parent_created=true
  fi
  [ ! -L "$legacy_skills_parent" ] && [ -d "$legacy_skills_parent" ] ||
    die "legacy skills directory is unsafe: $legacy_skills_parent"
  [ ! -e "$legacy_async_skill_destination" ] && [ ! -L "$legacy_async_skill_destination" ] ||
    die "legacy async handoff destination appeared during install: $legacy_async_skill_destination"

  mv "$legacy_async_skill_path" "$legacy_async_skill_destination" ||
    die 'could not retire the legacy async handoff skill'
  legacy_async_skill_retired=true
}

rollback_published() {
  if [ "$codex_published" = true ] && marker_matches "$codex_home"; then
    rm -rf "$codex_home" || true
  fi

  if [ "$legacy_async_skill_retired" = true ] && \
      [ ! -e "$legacy_async_skill_path" ] && [ -e "$legacy_async_skill_destination" ]; then
    mv "$legacy_async_skill_destination" "$legacy_async_skill_path" || true
  fi
  if [ "$legacy_skills_parent_created" = true ]; then
    rmdir "$codex_home/legacy-skills" 2>/dev/null || true
  fi

  rollback_index=$((${#upgrade_published_paths[@]} - 1))
  while [ "$rollback_index" -ge 0 ]; do
    rollback_path=${upgrade_published_paths[$rollback_index]}
    if marker_matches "$rollback_path"; then
      rm -rf "$rollback_path" || true
    fi
    rollback_index=$((rollback_index - 1))
  done
  if [ "$upgrade_pairing_backed_up" = true ] && [ -f "$upgrade_pairing_backup" ]; then
    mv -f "$upgrade_pairing_backup" "$codex_home/PAIRING.md" || true
  fi
  if [ "$upgrade_tools_parent_created" = true ]; then
    rmdir "$codex_home/tools" 2>/dev/null || true
  fi

  rollback_index=$((${#published_skills[@]} - 1))
  while [ "$rollback_index" -ge 0 ]; do
    rollback_path=$agents_skills_home/${published_skills[$rollback_index]}
    if marker_matches "$rollback_path"; then
      rm -rf "$rollback_path" || true
    fi
    rollback_index=$((rollback_index - 1))
  done

  [ "$created_skills_home" = true ] || return 0
  rmdir "$agents_skills_home" 2>/dev/null || true
  [ "$created_agents_home" = true ] || return 0
  rmdir "$agents_home" 2>/dev/null || true
}

cleanup() {
  status=$?
  trap - EXIT
  if [ "$status" -ne 0 ] && [ "$publish_started" = true ]; then
    rollback_published
  fi
  [ -z "$codex_stage" ] || rm -rf "$codex_stage" || true
  [ -z "$agents_stage" ] || rm -rf "$agents_stage" || true
  exit "$status"
}
trap cleanup EXIT

cp "$script_dir/codex/AGENTS.md" "$codex_stage/AGENTS.md"
cp "$script_dir/codex/PAIRING.md" "$codex_stage/PAIRING.md"
cp "$script_dir/codex/config.toml" "$codex_stage/config.toml"
cp -R "$script_dir/codex/hooks" "$codex_stage/hooks"
cp -R "$script_dir/codex/agents" "$codex_stage/agents"

for skill_name in "${skills_to_publish[@]}"; do
  cp -R "$script_dir/agents/skills/$skill_name" "$agents_stage/$skill_name"
done

run_codex() {
  CODEX_HOME="$codex_stage" codex "$@"
}

install_marketplaces() {
  marketplace_json=$(run_codex plugin marketplace list --json) ||
    die 'could not read installed plugin marketplaces'

  while IFS='|' read -r marketplace_name marketplace_source marketplace_ref; do
    case "$marketplace_name" in
      ''|'#'*) continue ;;
    esac

    [ -n "$marketplace_source" ] ||
      die "marketplace source is missing: $marketplace_name"
    [[ "$marketplace_ref" =~ ^[0-9a-f]{40}$ ]] ||
      die "marketplace ref must be a 40-character commit: $marketplace_name"

    case "$marketplace_json" in
      *"$marketplace_source"*) ;;
      *)
        run_codex plugin marketplace add "$marketplace_source" --ref "$marketplace_ref" ||
          die "could not install marketplace: $marketplace_name"
        ;;
    esac
  done < "$script_dir/plugins/marketplaces.tsv"
}

install_all_plugins() {
  while IFS= read -r plugin || [ -n "$plugin" ]; do
    case "$plugin" in
      ''|'#'*) continue ;;
    esac

    case "$plugin" in
      *@*) ;;
      *) die "invalid plugin entry: $plugin" ;;
    esac

    run_codex plugin add "$plugin" ||
      die "plugin installation failed: $plugin"
  done < "$script_dir/plugins/plugins.txt"
}

if [ "$codex_upgrade" = false ]; then
  install_marketplaces
  install_all_plugins
else
  printf '%s\n' 'Recognized existing Pair Codex state; preserving its installed plugins.' >&2
fi

mkdir -p "$(dirname -- "$tool_stage")" ||
  die 'could not create handoff tool staging directory'
gh repo clone "https://github.com/$expected_tool_repo.git" "$tool_stage" -- --branch main ||
  die "could not clone public handoff tool: $expected_tool_repo"
validate_tool_checkout "$tool_stage"

if [ -e "$agents_skills_home/handoff" ] || [ -L "$agents_skills_home/handoff" ]; then
  diff -qr "$agents_skills_home/handoff" "$tool_stage/skills/handoff" >/dev/null ||
    die "existing handoff skill differs; reconcile it manually: $agents_skills_home/handoff"
  printf '%s\n' 'Preserving existing global handoff skill.' >&2
else
  cp -R "$tool_stage/skills/handoff" "$agents_stage/handoff" ||
    die 'could not stage handoff skill from public tool'
  skills_to_publish+=(handoff)
fi

PAIR_CODEX_HOME="$codex_stage" fish "$tool_stage/scripts/pair-handoff.fish" \
  configure --storage-repo "$storage_repo" ||
  die "could not configure private handoff storage: $storage_repo"

publish_started=true
if [ "$codex_upgrade" = true ]; then
  publish_upgrade_codex_state
else
  mkdir "$codex_home" ||
    die "Codex destination appeared during install and was not replaced: $codex_home"
  mark_empty_destination "$codex_home" ||
    die "could not mark Codex destination: $codex_home"
  codex_published=true
  move_staged_contents "$codex_stage" "$codex_home" ||
    die 'could not publish staged Codex setup'
fi

if [ ! -e "$agents_home" ]; then
  mkdir "$agents_home"
  created_agents_home=true
fi
if [ ! -e "$agents_skills_home" ]; then
  mkdir "$agents_skills_home"
  created_skills_home=true
fi

for skill_name in "${skills_to_publish[@]}"; do
  staged_skill=$agents_stage/$skill_name
  skill_destination=$agents_skills_home/$skill_name
  mkdir "$skill_destination" ||
    die "skill appeared during install and was not replaced: $skill_destination"
  mark_empty_destination "$skill_destination" ||
    die "could not mark skill destination: $skill_destination"
  published_skills+=("$skill_name")
  move_staged_contents "$staged_skill" "$skill_destination" ||
    die "could not publish staged skill: $skill_name"
done

if [ "$codex_upgrade" = true ]; then
  retire_legacy_async_skill
fi

if [ "$codex_upgrade" = true ]; then
  for published_path in "${upgrade_published_paths[@]}"; do
    rm -f "$published_path/$transaction_marker"
  done
  [ -z "$upgrade_pairing_backup" ] || rm -f "$upgrade_pairing_backup"
else
  rm -f "$codex_home/$transaction_marker"
fi
for skill_name in "${published_skills[@]}"; do
  rm -f "$agents_skills_home/$skill_name/$transaction_marker"
done
publish_started=false

printf '%s\n' 'Installed Pair Codex with pinned plugins and private async handoff storage.'
printf '%s\n' 'Start Codex normally:'
printf '%s\n' '  codex'
printf '%s\n' "Then use \$handoff to send, receive, inspect, or reconfigure handoffs."
printf '%s\n' 'Optional isolated Pair Codex profile:'
printf '  CODEX_HOME="%s" codex\n' "$codex_home"
