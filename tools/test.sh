#!/bin/zsh

set -eu

SCRIPT_DIR="${0:A:h}"

exec "$SCRIPT_DIR/run_headless.sh" \
	--script res://tests/smoke_test.gd
