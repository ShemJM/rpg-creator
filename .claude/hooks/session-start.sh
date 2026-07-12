#!/bin/bash
set -euo pipefail

# Only needed in Claude Code web sessions — local machines manage their own Godot.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# Best-effort: a session whose network policy blocks the download must still
# start; make test then reports the missing binary with remediation steps.
bash scripts/setup-godot.sh ||
	echo "[session-start] Godot setup failed — headless runs unavailable this session (see message above)."
