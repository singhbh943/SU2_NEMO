#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
DEFAULT_PREFIX="$(cd "$ROOT/.." && pwd)/SU2_install"
PREFIX="${SU2_INSTALL_PREFIX:-$DEFAULT_PREFIX}"
JOBS="$(nproc)"
EXTRA=()

usage() {
  echo "Usage: ./scripts/update.sh [--prefix PATH] [--jobs N] [--install-pato-env] [--persist-shell]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --jobs) JOBS="${2:-}"; shift 2 ;;
    --install-pato-env) EXTRA+=("--install-pato-env"); shift ;;
    --persist-shell) EXTRA+=("--persist-shell"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

BRANCH="$(git -C "$ROOT" branch --show-current)"
[[ -n "$BRANCH" ]] || { echo "ERROR: detached HEAD; update by tag/commit manually" >&2; exit 10; }

if ! git -C "$ROOT" diff --ignore-submodules=dirty --quiet || ! git -C "$ROOT" diff --cached --ignore-submodules=dirty --quiet; then
  git -C "$ROOT" status --short
  echo "ERROR: tracked local source changes exist" >&2
  exit 11
fi

git -C "$ROOT" fetch origin "$BRANCH" --tags
git -C "$ROOT" merge --ff-only "origin/$BRANCH"
git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init --recursive

exec "$ROOT/scripts/install.sh" --prefix "$PREFIX" --jobs "$JOBS" "${EXTRA[@]}"
