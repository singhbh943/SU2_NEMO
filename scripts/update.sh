#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PREFIX="${SU2_NEMO_PREFIX:-$HOME/SU2_NEMO}"
JOBS="$(nproc)"

usage() {
  echo "Usage: ./scripts/update.sh [--prefix PATH] [--jobs N]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --jobs) JOBS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null
BRANCH="$(git -C "$ROOT" branch --show-current)"
[[ -n "$BRANCH" ]] || { echo "ERROR: detached HEAD; update by tag/commit manually" >&2; exit 10; }

if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
  git -C "$ROOT" status --short
  echo "ERROR: tracked local changes exist" >&2
  exit 11
fi

if [[ -d "$ROOT/subprojects/Mutationpp/.git" || -f "$ROOT/subprojects/Mutationpp/.git" ]]; then
  [[ -z "$(git -C "$ROOT/subprojects/Mutationpp" status --porcelain)" ]] || {
    echo "ERROR: local Mutation++ changes exist" >&2
    exit 12
  }
fi

git -C "$ROOT" fetch origin "$BRANCH" --tags
git -C "$ROOT" merge --ff-only "origin/$BRANCH"
git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init --recursive

exec "$ROOT/scripts/install.sh" --prefix "$PREFIX" --jobs "$JOBS"
