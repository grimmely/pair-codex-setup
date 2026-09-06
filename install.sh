#!/usr/bin/env bash

set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage: bash install.sh [options]

Install the portable Pair Codex setup without replacing existing state.

Options:
  --codex-home DIR  Destination for isolated Codex state.
                     Default: $HOME/.pair-codex
  --with-plugins    Fetch and install the pinned third-party plugins.
  --skip-plugins    Compatibility alias for the default core-only install.
  --help            Show this message.
EOF
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
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
with_plugins=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --codex-home)
      [ "$#" -ge 2 ] || die '--codex-home requires a directory'
      codex_home=$2
      shift 2
      ;;
    --with-plugins)
      with_plugins=true
      shift
      ;;
    --skip-plugins)
      with_plugins=false
      shift
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

validate_new_destination "$codex_home" 'Codex'
codex_home=$validated_destination
codex_parent=$(dirname -- "$codex_home")

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

transaction_marker='.pair-codex-install-marker'
transaction_id=${codex_stage##*/}
publish_started=false
codex_published=false
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

rollback_published() {
  if [ "$codex_published" = true ] && marker_matches "$codex_home"; then
    rm -rf "$codex_home" || true
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

if [ "$with_plugins" = true ]; then
  command -v codex >/dev/null 2>&1 ||
    die 'Codex CLI is required with --with-plugins; install and sign in first'
  install_marketplaces
  install_all_plugins
fi

publish_started=true
mkdir "$codex_home" ||
  die "Codex destination appeared during install and was not replaced: $codex_home"
printf '%s\n' "$transaction_id" > "$codex_home/$transaction_marker"
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
  printf '%s\n' "$transaction_id" > "$skill_destination/$transaction_marker"
  published_skills+=("$skill_name")
  move_staged_contents "$staged_skill" "$skill_destination" ||
    die "could not publish staged skill: $skill_name"
done

rm -f "$codex_home/$transaction_marker"
for skill_name in "${published_skills[@]}"; do
  rm -f "$agents_skills_home/$skill_name/$transaction_marker"
done
publish_started=false

printf 'Installed Pair Codex setup%s.\n' \
  "$( [ "$with_plugins" = true ] && printf ' with pinned plugins' )"
printf 'Start it with:\n'
printf '  CODEX_HOME="%s" codex\n' "$codex_home"
printf 'Then run /hooks and review the local SessionStart hook.\n'
