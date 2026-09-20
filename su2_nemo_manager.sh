#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CMD="${1:-help}"; shift || true
case "$CMD" in
  deps) exec "$ROOT/install_dependencies_ubuntu.sh" "$@" ;;
  install) exec "$ROOT/install_su2_nemo.sh" "$@" ;;
  update) exec "$ROOT/update_su2_nemo.sh" "$@" ;;
  verify) exec "$ROOT/verify_su2_nemo.sh" "$@" ;;
  tar) exec "$ROOT/make_su2_nemo_tarball.sh" "$@" ;;
  portable-update) exec "$ROOT/update_portable_su2_nemo.sh" "$@" ;;
  status)
    echo "SU2 source:"; git -C "$ROOT" log -1 --oneline
    echo "Mutation++:"; git -C "$ROOT/subprojects/Mutationpp" log -1 --oneline
    [ ! -f "$HOME/SU2_NEMO/runtime/VERSION" ] || { echo "Runtime:"; cat "$HOME/SU2_NEMO/runtime/VERSION"; }
    ;;
  *)
    cat <<HELP
Usage:
  ./su2_nemo_manager.sh deps
  ./su2_nemo_manager.sh install
  ./su2_nemo_manager.sh update
  ./su2_nemo_manager.sh verify
  ./su2_nemo_manager.sh tar
  ./su2_nemo_manager.sh portable-update
  ./su2_nemo_manager.sh status
HELP
    ;;
esac
