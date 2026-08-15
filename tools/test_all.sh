#!/bin/zsh

set -eu

SCRIPT_DIR="${0:A:h}"

"$SCRIPT_DIR/run_headless.sh" --script res://tests/engineer_abilities_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/exploration_system_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/combat_catalog_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/room_map_generator_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/power_network_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/lockdown_director_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/defense_loadout_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/engineer_toolkit_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/enemy_behavior_test.gd
"$SCRIPT_DIR/run_headless.sh" --script res://tests/movement_flow_test.gd
"$SCRIPT_DIR/test.sh"
