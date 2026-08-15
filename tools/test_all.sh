#!/bin/zsh

set -eu

SCRIPT_DIR="${0:A:h}"

"$SCRIPT_DIR/run_headless.sh" --script res://tests/engineer_abilities_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/exploration_system_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/combat_catalog_test.gd
"$SCRIPT_DIR/test.sh"
