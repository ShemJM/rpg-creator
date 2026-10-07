# Canonical commands for building and testing games headlessly.
# Used by humans, agents (see CLAUDE.md), and CI — keep these the single
# source of truth for how the headless runner is invoked.

GODOT ?= $(shell [ -x bin/godot ] && echo bin/godot || command -v godot || command -v godot4)
RUNNER := --headless --path . --
TIMEOUT ?= 120
# The whole-suite boots (--test-all) get longer as games accumulate.
TIMEOUT_ALL ?= 300

SCENARIOS := $(wildcard games/*_scenario.json)

PROJECTS := $(wildcard games/*.rpgm) $(wildcard games/*.rpgc)

# Legacy fixtures must keep validating too (integer command types / triggers).
LEGACY_FILES := tests/fixtures/legacy_project.rpgc tests/fixtures/legacy_scenario.json

TEST_TARGETS := validate-all test-validator test-roundtrip test-scenarios test-legacy test-watchdog test-database

.PHONY: help setup test $(TEST_TARGETS) validate run-scenario roundtrip list-maps list-database _need_godot

help:
	@echo "make setup                              # install/locate Godot (bin/godot)"
	@echo "make test                               # validate + run every games/*_scenario.json + database check"
	@echo "make validate P=games/foo.rpgc          # lint one project or scenario file"
	@echo "make validate-all                       # lint every project + scenario in games/"
	@echo "make roundtrip                          # check games/ re-serialize idempotently"
	@echo "make run-scenario S=games/foo_scenario.json"
	@echo "make list-maps P=games/foo.rpgm"
	@echo "make list-database P=games/foo.rpgc"

setup:
	bash scripts/setup-godot.sh

# Keep going after a failing sub-target so one bad file doesn't hide the
# results of everything else; the exit code still reflects any failure.
test: _need_godot
	@fail=0; \
	for t in $(TEST_TARGETS); do \
		echo "### make $$t"; \
		$(MAKE) --no-print-directory $$t || fail=1; \
	done; \
	if [ $$fail -eq 0 ]; then echo "### ALL TESTS PASSED"; else echo "### TESTS FAILED (see above)"; fi; \
	exit $$fail

_need_godot:
	@if [ -z "$(GODOT)" ]; then echo "No Godot binary — run 'make setup' first."; exit 1; fi

# Pre-v4 project files (integer command types/triggers) must keep loading.
test-legacy: _need_godot
	timeout $(TIMEOUT) $(GODOT) $(RUNNER) --test-all tests/fixtures

# Every project must survive load -> save -> load -> save unchanged, and the
# saved form must still validate (guards editor re-saves against format drift).
test-roundtrip: _need_godot
	timeout $(TIMEOUT) $(GODOT) $(RUNNER) --roundtrip-all games

roundtrip: test-roundtrip

# A scenario that never finishes must fail with exactly a "timeout" assertion (exit 1).
test-watchdog: _need_godot
	@mkdir -p bin
	@timeout $(TIMEOUT) $(GODOT) $(RUNNER) --scenario tests/watchdog/timeout_scenario.json --output bin/watchdog.json >/dev/null; \
	code=$$?; \
	if [ $$code -ne 1 ]; then echo "watchdog FAILED (exit $$code, expected 1)"; exit 1; fi; \
	if grep -q '"message": "timeout: scenario did not finish' bin/watchdog.json; then echo "watchdog timeout OK"; \
	else echo "watchdog FAILED: exit 1 but no timeout assertion in bin/watchdog.json"; exit 1; fi

# The validator must report exactly the known errors for the broken fixtures
# (a project and a scenario). Regenerate an expected file after deliberately
# changing validator messages:
#   $(GODOT) $(RUNNER) --validate tests/validator/broken_project.rpgc --output tests/validator/broken_project_expected.json
test-validator: _need_godot
	@mkdir -p bin
	@fail=0; \
	for name in broken_project.rpgc broken_scenario.json; do \
		base=$${name%.*}; \
		timeout $(TIMEOUT) $(GODOT) $(RUNNER) --validate tests/validator/$$name --output bin/$$base.errors.json >/dev/null; \
		code=$$?; \
		if [ $$code -ne 1 ]; then echo "validator FAILED to reject $$name (exit $$code, expected 1)"; fail=1; continue; fi; \
		if diff tests/validator/$${base}_expected.json bin/$$base.errors.json; then echo "validator errors for $$name match expected OK"; \
		else echo "validator errors for $$name differ from tests/validator/$${base}_expected.json"; fail=1; fi; \
	done; \
	exit $$fail

validate: _need_godot
	timeout $(TIMEOUT) $(GODOT) $(RUNNER) --validate $(P)

validate-all: _need_godot
	@fail=0; \
	for f in $(PROJECTS) $(SCENARIOS) $(LEGACY_FILES); do \
		echo "=== validate $$f"; \
		timeout $(TIMEOUT) $(GODOT) $(RUNNER) --validate $$f || fail=1; \
	done; \
	exit $$fail

# All scenarios in one engine boot (see headless_runner --test-all).
test-scenarios: _need_godot
	timeout $(TIMEOUT_ALL) $(GODOT) $(RUNNER) --test-all games

test-database: _need_godot
	@mkdir -p bin
	timeout $(TIMEOUT) $(GODOT) $(RUNNER) --project games/database_test.rpgc --list-database --output bin/db_summary.json >/dev/null
	diff games/database_test_expected.json bin/db_summary.json && echo "database summary OK"

run-scenario: _need_godot
	timeout $(TIMEOUT) $(GODOT) $(RUNNER) --scenario $(S)

list-maps: _need_godot
	$(GODOT) $(RUNNER) --project $(P) --list-maps

list-database: _need_godot
	$(GODOT) $(RUNNER) --project $(P) --list-database
