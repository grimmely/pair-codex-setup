#!/usr/bin/env bash

set -euo pipefail
umask 077

readonly setup_repo='https://github.com/grimmely/pair-codex-setup.git'

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    die "required command is not installed: $1"
}

cleanup() {
  if [ -n "${setup_checkout:-}" ] && [ -d "$setup_checkout" ]; then
    rm -rf -- "$setup_checkout"
  fi
}

require_command git
require_command mktemp

setup_checkout=$(mktemp -d "${TMPDIR:-/tmp}/pair-codex-setup.XXXXXX") ||
  die 'could not create a private setup checkout'
chmod 700 "$setup_checkout" || die 'could not secure the temporary setup checkout'
trap cleanup EXIT

git clone --depth 1 --branch main --single-branch "$setup_repo" "$setup_checkout" ||
  die 'could not clone Pair Codex Setup main'

if [ -L "$setup_checkout/install.sh" ] || [ ! -f "$setup_checkout/install.sh" ]; then
  die 'Pair Codex Setup main is missing a regular install.sh'
fi

if ! ( : </dev/tty ) 2>/dev/null; then
  die 'direct installation requires an interactive terminal for storage setup'
fi

bash "$setup_checkout/install.sh" "$@" </dev/tty
