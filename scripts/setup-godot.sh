#!/usr/bin/env bash
## Ensure a Godot 4.6 binary is available for headless authoring/test runs.
##
## Resolution order:
##   1. $GODOT env var (path to a runnable binary)
##   2. bin/godot (cached by a previous run of this script)
##   3. godot / godot4 on PATH
##   4. Download from the official GitHub releases into bin/godot
##
## On success, prints the resolved binary path on the last line of stdout
## and warms the Godot import cache (first --script run stalls otherwise).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

BIN_DIR="bin"
CACHED="$BIN_DIR/godot"

resolve() {
	if [[ -n "${GODOT:-}" ]] && "$GODOT" --version >/dev/null 2>&1; then
		echo "$GODOT"
		return
	fi
	if [[ -x "$CACHED" ]]; then
		echo "$CACHED"
		return
	fi
	local cand
	for cand in godot godot4; do
		if command -v "$cand" >/dev/null 2>&1; then
			command -v "$cand"
			return
		fi
	done
	echo ""
}

download() {
	# GODOT_VERSION may override; otherwise try patch releases newest-first.
	# shellcheck disable=SC2206
	local versions=(${GODOT_VERSION:-4.6.2 4.6.1 4.6})
	local ver repo url
	mkdir -p "$BIN_DIR"
	for ver in "${versions[@]}"; do
		for repo in godot godot-builds; do
			url="https://github.com/godotengine/${repo}/releases/download/${ver}-stable/Godot_v${ver}-stable_linux.x86_64.zip"
			echo "[setup-godot] Trying ${url}" >&2
			if curl -fsSL --retry 3 --retry-delay 2 -o "$BIN_DIR/godot.zip" "$url"; then
				unzip -oq "$BIN_DIR/godot.zip" -d "$BIN_DIR"
				mv "$BIN_DIR/Godot_v${ver}-stable_linux.x86_64" "$CACHED"
				chmod +x "$CACHED"
				rm -f "$BIN_DIR/godot.zip"
				return 0
			fi
		done
	done
	return 1
}

GODOT_BIN="$(resolve)"

if [[ -z "$GODOT_BIN" ]]; then
	if ! download; then
		cat >&2 <<'EOF'
[setup-godot] ERROR: No Godot binary found and download failed.

Fixes:
  - Local machine: install Godot 4.6 and put it on PATH (or set GODOT=/path/to/godot).
  - Claude Code web session: allow network access to github.com/godotengine
    in the environment's network policy, or preinstall Godot in the
    environment's setup script.
EOF
		exit 1
	fi
	GODOT_BIN="$CACHED"
fi

echo "[setup-godot] Using: $GODOT_BIN ($("$GODOT_BIN" --version 2>/dev/null | head -1))" >&2

# Warm the import cache so the first --script run doesn't stall importing assets.
if [[ ! -d .godot/imported ]]; then
	"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true
fi

echo "$GODOT_BIN"
