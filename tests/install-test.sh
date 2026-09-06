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
gh_log="$tmp_dir/gh.log"
mkdir -p "$fake_bin"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "${1:-} ${2:-}" = "login status" ]; then' \
  '  exit 0' \
  'fi' \
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
  'if [ "${1:-}" = "--version" ]; then' \
  '  printf "%s\\n" "fish, version 4.0.0"' \
  'fi' > "$fake_bin/fish"
chmod 755 "$fake_bin/fish"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "${1:-}" = "--help" ]; then' \
  '  exit 0' \
  'fi' \
  'exit 1' > "$fake_bin/codex-session-exporter"
chmod 755 "$fake_bin/codex-session-exporter"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "${1:-}" = "--version" ]; then' \
  '  printf "%s\\n" "${NODE_TEST_VERSION:-v22.0.0}"' \
  '  exit 0' \
  'fi' \
  'exit 1' > "$fake_bin/node"
chmod 755 "$fake_bin/node"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ -n "${GH_TEST_LOG:-}" ]; then' \
  '  printf "%s\\t" "$@" >> "$GH_TEST_LOG"' \
  '  printf "\\n" >> "$GH_TEST_LOG"' \
  'fi' \
  'if [ "${1:-} ${2:-}" = "auth status" ]; then' \
  '  exit 0' \
  'fi' \
  'if [ "${1:-} ${2:-} ${3:-}" = "repo view grimmely/pair-codex-handoffs" ]; then' \
  '  printf "true\\n"' \
  '  exit 0' \
  'fi' \
  'if [ "${1:-} ${2:-} ${3:-}" = "repo clone grimmely/pair-codex-handoffs" ]; then' \
  '  destination=${4:?missing clone destination}' \
  '  git init -q "$destination"' \
  '  git -C "$destination" remote add origin https://github.com/grimmely/pair-codex-handoffs.git' \
  '  mkdir -p "$destination/scripts"' \
  '  printf "%s\\n" "argparse '\''codex-home='\'' -- \$argv" > "$destination/scripts/handoff.fish"' \
  '  printf "%s\\n" "argparse '\''codex-home='\'' -- \$argv" > "$destination/scripts/receive.fish"' \
  '  exit 0' \
  'fi' \
  'exit 1' > "$fake_bin/gh"
chmod 755 "$fake_bin/gh"

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
  'if [ "${PAIR_CODEX_TEST_FAIL_MARKER_DESTINATION:-}" = "${1:-}" ]; then' \
  '  /bin/mkdir "$1"' \
  '  /bin/ln -s "$1" "$1/.pair-codex-install-marker"' \
  '  exit 0' \
  'fi' \
  'exec /bin/mkdir "$@"' > "$fake_bin/mkdir"
chmod 755 "$fake_bin/mkdir"

core_home="$tmp_dir/core-user"
core_codex_home="$tmp_dir/core-codex"
mkdir -p "$core_home"
: > "$plugin_log"
: > "$gh_log"
HOME="$core_home" PATH="$fake_bin:$PATH" CODEX_TEST_LOG="$plugin_log" \
  GH_TEST_LOG="$gh_log" \
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
test -f "$core_home/.agents/skills/async-pair-handoff/SKILL.md" || \
  fail 'async handoff skill was not installed'
rg -F -- 'The Fish scripts use `CODEX_HOME` when set' \
  "$core_home/.agents/skills/async-pair-handoff/SKILL.md" >/dev/null || \
  fail 'async handoff skill does not target the active Codex home'
test -f "$core_home/pair-codex-handoffs/scripts/handoff.fish" || \
  fail 'shared handoff checkout was not installed'
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
grep -Fq 'superpowers@claude-plugins-official' "$plugin_log" || \
  fail 'Claude marketplace plugins were not installed by default'
grep -Fq $'plugin\tmarketplace\tadd\thttps://github.com/anthropics/claude-plugins-official.git\t--ref\t0e3f501d0f4acb2a3406f645b1e0f80056c22e8c' "$plugin_log" || \
  fail 'marketplace was not installed at its pinned commit'
if grep -Fq 'browser@openai-bundled' "$plugin_log"; then
  fail 'host-managed plugins should not be installed from this bundle'
fi
grep -Fq $'auth\tstatus\t--hostname\tgithub.com' "$gh_log" || \
  fail 'GitHub authentication was not checked'
grep -Fq $'repo\tclone\tgrimmely/pair-codex-handoffs' "$gh_log" || \
  fail 'shared handoff repository was not cloned'

missing_home="$tmp_dir/missing-user"
missing_codex_home="$tmp_dir/missing-codex"
missing_bin="$tmp_dir/missing-bin"
mkdir -p "$missing_home" "$missing_bin"
cp "$fake_bin/codex" "$fake_bin/fish" "$fake_bin/gh" "$fake_bin/node" \
  "$missing_bin/"
if HOME="$missing_home" PATH="$missing_bin:/usr/bin:/bin" \
  CODEX_TEST_LOG="$plugin_log" GH_TEST_LOG="$gh_log" \
  bash "$repo_root/install.sh" --codex-home "$missing_codex_home"; then
  fail 'missing exporter reported success'
fi
test ! -e "$missing_codex_home" || \
  fail 'missing exporter published Codex state'
test ! -e "$missing_home/.agents/skills" || \
  fail 'missing exporter published skills'
test ! -e "$missing_home/pair-codex-handoffs" || \
  fail 'missing exporter cloned a handoff checkout'

old_node_home="$tmp_dir/old-node-user"
old_node_codex_home="$tmp_dir/old-node-codex"
mkdir -p "$old_node_home"
if HOME="$old_node_home" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" GH_TEST_LOG="$gh_log" \
  NODE_TEST_VERSION='v18.20.0' \
  bash "$repo_root/install.sh" --codex-home "$old_node_codex_home"; then
  fail 'Node older than 22 reported success'
fi
test ! -e "$old_node_codex_home" || \
  fail 'old Node published Codex state'
test ! -e "$old_node_home/.agents/skills" || \
  fail 'old Node published skills'
test ! -e "$old_node_home/pair-codex-handoffs" || \
  fail 'old Node cloned a handoff checkout'

insecure_remote_home="$tmp_dir/insecure-remote-user"
insecure_remote_codex_home="$tmp_dir/insecure-remote-codex"
insecure_handoff_home="$insecure_remote_home/pair-codex-handoffs"
mkdir -p "$insecure_handoff_home/scripts"
git init -q "$insecure_handoff_home"
git -C "$insecure_handoff_home" remote add origin \
  http://github.com/grimmely/pair-codex-handoffs.git
printf "%s\\n" "argparse 'codex-home=' -- \$argv" \
  > "$insecure_handoff_home/scripts/handoff.fish"
printf "%s\\n" "argparse 'codex-home=' -- \$argv" \
  > "$insecure_handoff_home/scripts/receive.fish"
if HOME="$insecure_remote_home" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" GH_TEST_LOG="$gh_log" \
  bash "$repo_root/install.sh" --codex-home "$insecure_remote_codex_home"; then
  fail 'plaintext handoff remote reported success'
fi
test ! -e "$insecure_remote_codex_home" || \
  fail 'plaintext handoff remote published Codex state'
test ! -e "$insecure_remote_home/.agents/skills" || \
  fail 'plaintext handoff remote published skills'

legacy_home="$tmp_dir/legacy-user"
legacy_codex_home="$tmp_dir/legacy-codex"
legacy_handoff_home="$legacy_home/pair-codex-sessions"
mkdir -p "$legacy_handoff_home"
git init -q "$legacy_handoff_home"
git -C "$legacy_handoff_home" remote add origin \
  https://github.com/grimmely/sapiom-pair-codex-sessions.git
if HOME="$legacy_home" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" GH_TEST_LOG="$gh_log" \
  bash "$repo_root/install.sh" --codex-home "$legacy_codex_home"; then
  fail 'legacy handoff checkout reported success'
fi
test -d "$legacy_handoff_home" || \
  fail 'legacy handoff checkout was moved or removed'
test ! -e "$legacy_codex_home" || \
  fail 'legacy handoff checkout published Codex state'
test ! -e "$legacy_home/.agents/skills" || \
  fail 'legacy handoff checkout published skills'
test ! -e "$legacy_home/pair-codex-handoffs" || \
  fail 'legacy handoff checkout created a new checkout'

dual_legacy_home="$tmp_dir/dual-legacy-user"
dual_legacy_codex_home="$tmp_dir/dual-legacy-codex"
dual_legacy_checkout="$dual_legacy_home/pair-codex-sessions"
dual_new_checkout="$dual_legacy_home/pair-codex-handoffs"
mkdir -p "$dual_legacy_checkout" "$dual_new_checkout/scripts"
git init -q "$dual_legacy_checkout"
git -C "$dual_legacy_checkout" remote add origin \
  https://github.com/grimmely/sapiom-pair-codex-sessions.git
git init -q "$dual_new_checkout"
git -C "$dual_new_checkout" remote add origin \
  https://github.com/grimmely/pair-codex-handoffs.git
printf "%s\\n" "argparse 'codex-home=' -- \$argv" \
  > "$dual_new_checkout/scripts/handoff.fish"
printf "%s\\n" "argparse 'codex-home=' -- \$argv" \
  > "$dual_new_checkout/scripts/receive.fish"
if HOME="$dual_legacy_home" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" GH_TEST_LOG="$gh_log" \
  bash "$repo_root/install.sh" --codex-home "$dual_legacy_codex_home"; then
  fail 'legacy handoff checkout beside new checkout reported success'
fi
test -d "$dual_legacy_checkout" || \
  fail 'legacy handoff checkout beside new checkout was moved or removed'
test -d "$dual_new_checkout" || \
  fail 'new handoff checkout was moved or removed'
test ! -e "$dual_legacy_codex_home" || \
  fail 'legacy handoff checkout beside new checkout published Codex state'
test ! -e "$dual_legacy_home/.agents/skills" || \
  fail 'legacy handoff checkout beside new checkout published skills'

for removed_option in --with-plugins --skip-plugins; do
  removed_home="$tmp_dir/removed-${removed_option#--}"
  removed_codex_home="$tmp_dir/removed-${removed_option#--}-codex"
  mkdir -p "$removed_home"
  if HOME="$removed_home" PATH="$fake_bin:$PATH" \
    CODEX_TEST_LOG="$plugin_log" GH_TEST_LOG="$gh_log" \
    bash "$repo_root/install.sh" "$removed_option" \
    --codex-home "$removed_codex_home"; then
    fail "removed option reported success: $removed_option"
  fi
  test ! -e "$removed_codex_home" || \
    fail "removed option published Codex state: $removed_option"
done

failed_home="$tmp_dir/failed-user"
failed_codex_home="$tmp_dir/failed-codex"
mkdir -p "$failed_home"
: > "$plugin_log"
if HOME="$failed_home" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" \
  CODEX_TEST_FAIL_PLUGIN='superpowers@claude-plugins-official' \
  bash "$repo_root/install.sh" \
  --codex-home "$failed_codex_home"; then
  fail 'plugin failure reported success'
fi
test ! -e "$failed_codex_home" || fail 'failed install left Codex state'
test ! -e "$failed_home/.agents/skills/to-tickets" || \
  fail 'failed install left user skills'
test ! -e "$failed_home/pair-codex-handoffs" || \
  fail 'failed plugin install left a handoff checkout'
HOME="$failed_home" PATH="$fake_bin:$PATH" CODEX_TEST_LOG="$plugin_log" \
  bash "$repo_root/install.sh" --codex-home "$failed_codex_home"
test -f "$failed_codex_home/AGENTS.md" || \
  fail 'retry after failed plugin install did not work'

marker_failure_home="$tmp_dir/marker-failure-user"
marker_failure_codex_home="$tmp_dir/marker-failure-codex"
marker_failure_codex_canonical=$(CDPATH='' cd -P -- "$(dirname -- "$marker_failure_codex_home")" && pwd)
marker_failure_codex_canonical=$marker_failure_codex_canonical/$(basename -- "$marker_failure_codex_home")
mkdir -p "$marker_failure_home"
if HOME="$marker_failure_home" PATH="$fake_bin:$PATH" \
  CODEX_TEST_LOG="$plugin_log" GH_TEST_LOG="$gh_log" \
  PAIR_CODEX_TEST_FAIL_MARKER_DESTINATION="$marker_failure_codex_canonical" \
  bash "$repo_root/install.sh" --codex-home "$marker_failure_codex_home"; then
  fail 'marker-write failure reported success'
fi
test ! -e "$marker_failure_codex_home" || \
  fail 'marker-write failure left Codex state'
test ! -e "$marker_failure_home/.agents/skills" || \
  fail 'marker-write failure published skills'
test ! -e "$marker_failure_home/pair-codex-handoffs" || \
  fail 'marker-write failure published a handoff checkout'

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

printf 'PASS: complete install, retry safety, and collision safety\n'
