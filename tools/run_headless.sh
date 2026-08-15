#!/bin/zsh

set -eu

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
GODOT_BIN="/Applications/Godot.app/Contents/MacOS/godot"
LOG_DIR="$PROJECT_DIR/.godot/test-logs"

mkdir -p "$LOG_DIR"

if [[ ! -x "$GODOT_BIN" ]]; then
	print -u2 "Godot was not found at: $GODOT_BIN"
	exit 1
fi

ENGINE_LOG="$LOG_DIR/headless.log"
CONSOLE_LOG="$LOG_DIR/console.log"

set +e
"$GODOT_BIN" \
	--headless \
	--path "$PROJECT_DIR" \
	--log-file "$ENGINE_LOG" \
	"$@" >"$CONSOLE_LOG" 2>&1
EXIT_CODE=$?
set -e

# Godot 4.5 on macOS can emit this harmless Keychain/certificate message in a
# restricted shell. Keep it in console.log, but do not present it as a game error.
	sed \
	-e '/ERROR: Condition "ret != noErr" is true. Returning: ""/d' \
	-e '/at: get_system_ca_certificates (platform\/macos\/os_macos.mm:/d' \
	"$CONSOLE_LOG"

exit "$EXIT_CODE"
