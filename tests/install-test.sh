#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

directory_mode() {
  case "$(uname -s)" in
    Darwin) stat -f '%Lp' "$1" ;;
    *) stat -c '%a' "$1" ;;
  esac
}

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/pair-codex-test.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
plugin_log="$tmp_dir/plugin.log"
mkdir -p "$fake_bin"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "${1:-} ${2:-} ${3:-}" = "plugin marketplace list" ]; then' \
  '  printf "{\\"marketplaces\\":[]}\\n"' \
  '  exit 0' \
  'fi' \
  'if [ "${1:-} ${2:-}" = "plugin add" ] &&' \
  '   [ "${CODEX_TEST_FAIL_PLUGIN:-}" = "${3:-}" ]; then' \
  '  exit 1' \
  'fi' \
  'printf "%s\\t" "$@" >> "$CODEX_TEST_LOG"' \
  'printf "\\n" >> "$CODEX_TEST_LOG"' > "$fake_bin/codex"
chmod 755 "$fake_bin/codex"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "${PAIR_CODEX_TEST_FAIL_MOVE_DESTINATION:-}" = "${2:-}" ]; then' \
  '  exit 1' \
  'fi' \
  'exec /bin/mv "$@"' > "$fake_bin/mv"
chmod 755 "$fake_bin/mv"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "${PAIR_CODEX_TEST_RACE_DESTINATION:-}" = "${1:-}" ]; then' \
  '  /bin/mkdir "$1"' \
  '  exit 1' \
  'fi' \
  'exec /bin/mkdir "$@"' > "$fake_bin/mkdir"
chmod 755 "$fake_bin/mkdir"

core_home="$tmp_dir/core-user"
core_codex_home="$tmp_dir/core-codex"
mkdir -p "$core_home"
: > "$plugin_log"
HOME="$core_home" PATH="$fake_bin:$PATH" CODEX_TEST_LOG="$plugin_log" \
  bash "$repo_root/install.sh" \
  --codex-home "$core_codex_home"

test -f "$core_codex_home/AGENTS.md" || fail 'AGENTS.md was not installed'
test -f "$core_codex_home/config.toml" || fail 'config.toml was not installed'
test -f "$core_codex_home/hooks/feedback-learning.sh" || fail 'hook was not installed'
test -f "$core_codex_home/agents/pair-programmer.toml" || fail 'agent roles were not installed'
test "$(directory_mode "$core_codex_home")" = 700 || \
  fail 'Codex destination is not private'
test -f "$core_home/.agents/skills/to-tickets/SKILL.md" || \
  fail 'skills were not installed'
test -f "$core_home/.agents/skills/grilling/SKILL.md" || \
  fail 'grilling skill was not installed'
test ! -e "$core_home/.agents/skills/continuous-learning-v2" || \
  fail 'broad automation skill was installed'
if rg -n '^[[:space:]]*(rm -rf|go mod tidy -v|go get package@|go clean -modcache|cargo update|\./mvnw clean install -U|\./gradlew build --refresh-dependencies)' \
  "$repo_root/codex/agents"; then
  fail 'agent roles contain an unguarded destructive recovery command'
fi
test ! -e "$core_codex_home/auth.json" || fail 'authentication state was copied'
test ! -e "$core_codex_home/.pair-codex-install-marker" || \
  fail 'Codex transaction marker was not removed'
test ! -e "$core_home/.agents/skills/grilling/.pair-codex-install-marker" || \
  fail 'skill transaction marker was not removed'
cmp "$repo_root/codex/AGENTS.md" "$core_codex_home/AGENTS.md" || \
  fail 'AGENTS mismatch'
test ! -s "$plugin_log" || fail 'plugins require explicit opt-in'

plugin_home="$tmp_dir/plugin-user"
plugin_codex_home="$tmp_dir/plugin-codex"
mkdir -p "$plugin_home"
: > "$plugin_log"
HOME="$plugin_home" PATH="$fake_bin:$PATH" CODEX_TEST_LOG="$plugin_log" \
  bash "$repo_root/install.sh" \
  --with-plugins \
  --codex-home "$plugin_codex_home"
grep -Fq 'superpowers@claude-plugins-official' "$plugin_log" || \
  fail 'Claude marketplace plugins were not installed'
grep -Fq $'plugin\tmarketplace\tadd\thttps://github.com/anthropics/claude-plugins-official.git\t--ref\t0e3f501d0f4acb2a3406f645b1e0f80056c22e8c' "$plugin_log" || \
  fail 'marketplace was not installed at its pinned commit'
if grep -Fq 'browser@openai-bundled' "$plugin_log"; then
  fail 'host-managed plugins should not be installed from this bundle'
fi

failed_home="$tmp_dir/failed-user"
failed_codex_home="$tmp_dir/failed-codex"
mkdir -p "$failed_home"
: > "$plugin_log"
if HOME="$failed_home" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" \
  CODEX_TEST_FAIL_PLUGIN='superpowers@claude-plugins-official' \
  bash "$repo_root/install.sh" \
  --with-plugins \
  --codex-home "$failed_codex_home"; then
  fail 'plugin failure reported success'
fi
test ! -e "$failed_codex_home" || fail 'failed install left Codex state'
test ! -e "$failed_home/.agents/skills/to-tickets" || \
  fail 'failed install left user skills'
HOME="$failed_home" PATH="$fake_bin:$PATH" CODEX_TEST_LOG="$plugin_log" \
  bash "$repo_root/install.sh" --codex-home "$failed_codex_home"
test -f "$failed_codex_home/AGENTS.md" || \
  fail 'retry after failed plugin install did not work'

publish_home="$tmp_dir/publish-user"
publish_codex_home="$tmp_dir/publish-codex"
publish_failure_destination="$publish_home/.agents/skills/unslop"
mkdir -p "$publish_home"
if HOME="$publish_home" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" \
  PAIR_CODEX_TEST_FAIL_MOVE_DESTINATION="$publish_failure_destination" \
  bash "$repo_root/install.sh" --codex-home "$publish_codex_home"; then
  fail 'publication failure reported success'
fi
test ! -e "$publish_codex_home" || \
  fail 'publication failure left Codex state'
test ! -e "$publish_home/.agents/skills/grilling" || \
  fail 'publication failure left a skill'
HOME="$publish_home" PATH="$fake_bin:$PATH" CODEX_TEST_LOG="$plugin_log" \
  bash "$repo_root/install.sh" --codex-home "$publish_codex_home"
test -f "$publish_codex_home/AGENTS.md" || \
  fail 'retry after publication failure did not work'

race_home="$tmp_dir/race-user"
race_codex_home="$tmp_dir/race-codex"
race_codex_parent=$(CDPATH='' cd -P -- "$(dirname -- "$race_codex_home")" && pwd)
race_codex_canonical=$race_codex_parent/$(basename -- "$race_codex_home")
mkdir -p "$race_home"
if HOME="$race_home" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" \
  PAIR_CODEX_TEST_RACE_DESTINATION="$race_codex_canonical" \
  bash "$repo_root/install.sh" --codex-home "$race_codex_home"; then
  fail 'destination race reported success'
fi
test -d "$race_codex_home" || fail 'race fixture did not reserve destination'
test ! -e "$race_codex_home/AGENTS.md" || \
  fail 'destination race published Codex files'
test ! -e "$race_home/.agents/skills/grilling" || \
  fail 'destination race published user skills'

collision_home="$tmp_dir/collision-codex-home"
collision_user_home="$tmp_dir/collision-user"
mkdir -p "$collision_home" "$collision_user_home"
printf 'existing instructions\n' > "$collision_home/AGENTS.md"
if HOME="$collision_user_home" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" \
  bash "$repo_root/install.sh" \
  --codex-home "$collision_home"; then
  fail 'installer overwrote an existing setup'
fi
grep -Fqx 'existing instructions' "$collision_home/AGENTS.md" || \
  fail 'existing instructions changed'

link_target="$tmp_dir/destination-target"
link_destination="$tmp_dir/destination-link"
mkdir -p "$link_target"
ln -s "$link_target" "$link_destination"
if HOME="$tmp_dir/link-user" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" \
  bash "$repo_root/install.sh" --codex-home "$link_destination"; then
  fail 'installer accepted a symbolic-link destination'
fi

link_dir="$tmp_dir/symlink"
link_home="$tmp_dir/symlink-user"
link_codex_home="$tmp_dir/symlink-codex"
mkdir -p "$link_dir" "$link_home"
ln -s "$repo_root/install.sh" "$link_dir/install.sh"
HOME="$link_home" PATH="$fake_bin:$PATH" CODEX_TEST_LOG="$plugin_log" \
  bash "$link_dir/install.sh" --codex-home "$link_codex_home"
test -f "$link_codex_home/AGENTS.md" || \
  fail 'symlink invocation did not use the trusted bundle root'

printf 'PASS: portable install, retry safety, and collision safety\n'
