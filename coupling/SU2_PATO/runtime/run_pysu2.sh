#!/usr/bin/env bash

ROOT="${SU2_ROOT:-$HOME/SU2/SU2}"

export PYTHONPATH="$ROOT/build/SU2_PY/pySU2${PYTHONPATH:+:$PYTHONPATH}"

exec /usr/bin/python3 "$@"
