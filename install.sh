#!/usr/bin/env bash

set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage: bash install.sh [options]

Install the complete Pair Codex Sessions setup without replacing existing state.

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

validate_handoff_checkout() {
  local checkout_path checkout_root checkout_remote checkout_slug
  local handoff_script script_path script_content
  checkout_path=$1
  [ ! -L "$checkout_path" ] ||
    die "handoff checkout must not be a symbolic link: $checkout_path"
  [ -d "$checkout_path" ] ||
    die "handoff checkout is not a directory: $checkout_path"

  checkout_root=$(git -C "$checkout_path" rev-parse --show-toplevel 2>/dev/null) ||
    die "handoff checkout is not a Git repository: $checkout_path"
  checkout_root=$(CDPATH='' cd -P -- "$checkout_root" && pwd) ||
    die "cannot resolve handoff checkout: $checkout_path"
  checkout_path=$(CDPATH='' cd -P -- "$checkout_path" && pwd) ||
    die "cannot resolve handoff checkout: $checkout_path"
  [ "$checkout_root" = "$checkout_path" ] ||
    die "handoff checkout must be its Git repository root: $checkout_path"

  checkout_remote=$(git -C "$checkout_path" remote get-url origin 2>/dev/null) ||
    die "handoff checkout has no origin remote: $checkout_path"
  checkout_slug=$(github_slug_from_remote "$checkout_remote") ||
    die "handoff checkout origin must use SSH or HTTPS for GitHub: $checkout_path"
  [ "$checkout_slug" = "$expected_handoff_repo" ] ||
    die "handoff checkout origin must be: $expected_handoff_repo"

  for handoff_script in handoff.fish receive.fish; do
    script_path=$checkout_path/scripts/$handoff_script
    [ -f "$script_path" ] ||
      die "handoff checkout is missing: scripts/$handoff_script"
    script_content=$(< "$script_path") ||
      die "could not read handoff script: $script_path"
    case "$script_content" in
      *"'codex-home='"*) ;;
      *) die "handoff script lacks --codex-home support: $script_path" ;;
    esac
  done
}

is_legacy_handoff_checkout() {
  local checkout_path checkout_remote checkout_slug
  checkout_path=$1
  [ ! -L "$checkout_path" ] || return 1
  [ -d "$checkout_path" ] || return 1

  checkout_remote=$(git -C "$checkout_path" remote get-url origin 2>/dev/null) ||
    return 1
  checkout_slug=$(github_slug_from_remote "$checkout_remote") ||
    return 1
  [ "$checkout_slug" = "$legacy_handoff_repo" ] ||
    [ "$checkout_slug" = "$expected_handoff_repo" ]
}

require_complete_environment() {
  local required_command handoff_repo_private
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

  handoff_repo_private=$(gh repo view "$expected_handoff_repo" --json isPrivate --jq '.isPrivate' 2>/dev/null) ||
    die "cannot access private handoff repository: $expected_handoff_repo"
  [ "$handoff_repo_private" = true ] ||
    die "handoff repository must be private: $expected_handoff_repo"
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

script_dir=$(resolve_script_dir)
codex_home="$HOME/.pair-codex"
expected_handoff_repo='grimmely/pair-codex-handoffs'
legacy_handoff_repo='grimmely/sapiom-pair-codex-sessions'

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
  "$script_dir/agents/skills/async-pair-handoff" \
  "$script_dir/plugins/marketplaces.tsv" \
  "$script_dir/plugins/plugins.txt"; do
  [ -e "$required" ] || die "bundle is incomplete: $required"
done

validate_new_destination "$codex_home" 'Codex'
codex_home=$validated_destination
codex_parent=$(dirname -- "$codex_home")

require_complete_environment

handoff_home="$HOME/pair-codex-handoffs"
legacy_handoff_home="$HOME/pair-codex-sessions"
if is_legacy_handoff_checkout "$legacy_handoff_home"; then
  die "legacy handoff checkout detected at $legacy_handoff_home; reconcile it with $handoff_home before installing"
fi
[ ! -L "$handoff_home" ] ||
  die "handoff checkout must not be a symbolic link: $handoff_home"
handoff_needs_clone=false
if [ -e "$handoff_home" ]; then
  validate_handoff_checkout "$handoff_home"
else
  handoff_parent=$(dirname -- "$handoff_home")
  [ -d "$handoff_parent" ] ||
    die "handoff checkout parent does not exist: $handoff_parent"
  [ -w "$handoff_parent" ] ||
    die "handoff checkout parent is not writable: $handoff_parent"
  handoff_parent=$(CDPATH='' cd -P -- "$handoff_parent" && pwd) ||
    die "cannot resolve handoff checkout parent: $handoff_parent"
  handoff_home=$handoff_parent/$(basename -- "$handoff_home")
  handoff_needs_clone=true
fi

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

for source_skill in "$script_dir"/agents/skills/*; do
  [ -d "$source_skill" ] || die "invalid skill in bundle: $source_skill"
  skill_name=${source_skill##*/}
  if [ -e "$agents_skills_home/$skill_name" ] || \
     [ -L "$agents_skills_home/$skill_name" ]; then
    die "skill already exists and will not be replaced: $agents_skills_home/$skill_name"
  fi
done

codex_stage=$(mktemp -d "$codex_parent/.pair-codex-stage.XXXXXX") ||
  die 'cannot create Codex staging directory'
agents_stage=$(mktemp -d "$agents_parent/.pair-codex-skills-stage.XXXXXX") ||
  die 'cannot create skills staging directory'
handoff_stage_parent=''
handoff_stage=''
if [ "$handoff_needs_clone" = true ]; then
  handoff_stage_parent=$(mktemp -d "$handoff_parent/.pair-codex-handoff-stage.XXXXXX") ||
    die 'cannot create handoff checkout staging directory'
  handoff_stage=$handoff_stage_parent/pair-codex-handoffs
fi

transaction_marker='.pair-codex-install-marker'
transaction_id=${codex_stage##*/}
publish_started=false
codex_published=false
handoff_published=false
created_agents_home=false
created_skills_home=false
published_skills=()

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

rollback_published() {
  if [ "$codex_published" = true ] && marker_matches "$codex_home"; then
    rm -rf "$codex_home" || true
  fi

  if [ "$handoff_published" = true ] && marker_matches "$handoff_home"; then
    rm -rf "$handoff_home" || true
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
  [ -z "$handoff_stage_parent" ] || rm -rf "$handoff_stage_parent" || true
  exit "$status"
}
trap cleanup EXIT

cp "$script_dir/codex/AGENTS.md" "$codex_stage/AGENTS.md"
cp "$script_dir/codex/PAIRING.md" "$codex_stage/PAIRING.md"
cp "$script_dir/codex/config.toml" "$codex_stage/config.toml"
cp -R "$script_dir/codex/hooks" "$codex_stage/hooks"
cp -R "$script_dir/codex/agents" "$codex_stage/agents"

for source_skill in "$script_dir"/agents/skills/*; do
  skill_name=${source_skill##*/}
  cp -R "$source_skill" "$agents_stage/$skill_name"
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

install_marketplaces
install_all_plugins

if [ "$handoff_needs_clone" = true ]; then
  gh repo clone "$expected_handoff_repo" "$handoff_stage" ||
    die "could not clone private handoff repository: $expected_handoff_repo"
  validate_handoff_checkout "$handoff_stage"
fi

publish_started=true
mkdir "$codex_home" ||
  die "Codex destination appeared during install and was not replaced: $codex_home"
mark_empty_destination "$codex_home" ||
  die "could not mark Codex destination: $codex_home"
codex_published=true
move_staged_contents "$codex_stage" "$codex_home" ||
  die 'could not publish staged Codex setup'

if [ ! -e "$agents_home" ]; then
  mkdir "$agents_home"
  created_agents_home=true
fi
if [ ! -e "$agents_skills_home" ]; then
  mkdir "$agents_skills_home"
  created_skills_home=true
fi

for staged_skill in "$agents_stage"/*; do
  skill_name=${staged_skill##*/}
  skill_destination=$agents_skills_home/$skill_name
  mkdir "$skill_destination" ||
    die "skill appeared during install and was not replaced: $skill_destination"
  mark_empty_destination "$skill_destination" ||
    die "could not mark skill destination: $skill_destination"
  published_skills+=("$skill_name")
  move_staged_contents "$staged_skill" "$skill_destination" ||
    die "could not publish staged skill: $skill_name"
done

if [ "$handoff_needs_clone" = true ]; then
  mkdir "$handoff_home" ||
    die "handoff checkout appeared during install and was not replaced: $handoff_home"
  mark_empty_destination "$handoff_home" ||
    die "could not mark handoff checkout: $handoff_home"
  handoff_published=true
  move_staged_contents "$handoff_stage" "$handoff_home" ||
    die 'could not publish handoff checkout'
fi

rm -f "$codex_home/$transaction_marker"
for skill_name in "${published_skills[@]}"; do
  rm -f "$agents_skills_home/$skill_name/$transaction_marker"
done
if [ "$handoff_published" = true ]; then
  rm -f "$handoff_home/$transaction_marker"
fi
publish_started=false

printf '%s\n' 'Installed Pair Codex Sessions with pinned plugins and async handoff.'
printf 'Start it with:\n'
printf '  CODEX_HOME="%s" codex\n' "$codex_home"
printf 'Then run /hooks and review the local SessionStart hook.\n'
