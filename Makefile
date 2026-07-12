# Canonical commands for building and testing games headlessly.
# Used by humans, agents (see CLAUDE.md), and CI — keep these the single
# source of truth for how the headless runner is invoked.

GODOT ?= $(shell [ -x bin/godot ] && echo bin/godot || command -v godot || command -v godot4)
RUNNER := --headless --path . --
TIMEOUT ?= 120

SCENARIOS := $(wildcard games/*_scenario.json)

PROJECTS := $(wildcard games/*.rpgm) $(wildcard games/*.rpgc)

.PHONY: help setup test test-scenarios test-database test-validator validate validate-all run-scenario list-maps list-database

help:
	@echo "make setup                              # install/locate Godot (bin/godot)"
	@echo "make test                               # validate + run every games/*_scenario.json + database check"
	@echo "make validate P=games/foo.rpgc          # lint one project or scenario file"
	@echo "make validate-all                       # lint every project + scenario in games/"
	@echo "make run-scenario S=games/foo_scenario.json"
	@echo "make list-maps P=games/foo.rpgm"
	@echo "make list-database P=games/foo.rpgc"

setup:
	bash scripts/setup-godot.sh

test: validate-all test-validator test-scenarios test-database

# The validator must reject a deliberately broken project (exit 1, not 0/2).
test-validator:
	@timeout $(TIMEOUT) $(GODOT) $(RUNNER) --validate tests/fixtures/broken_project.rpgc >/dev/null; \
	code=$$?; \
	if [ $$code -eq 1 ]; then echo "validator rejects broken fixture OK"; \
	else echo "validator FAILED to reject broken fixture (exit $$code)"; exit 1; fi

validate:
	timeout $(TIMEOUT) $(GODOT) $(RUNNER) --validate $(P)

validate-all:
	@fail=0; \
	for f in $(PROJECTS) $(SCENARIOS); do \
		echo "=== validate $$f"; \
		timeout $(TIMEOUT) $(GODOT) $(RUNNER) --validate $$f || fail=1; \
	done; \
	exit $$fail

test-scenarios:
	@if [ -z "$(GODOT)" ]; then echo "No Godot binary — run 'make setup' first."; exit 1; fi
	@fail=0; \
	for s in $(SCENARIOS); do \
		echo "=== $$s"; \
		timeout $(TIMEOUT) $(GODOT) $(RUNNER) --scenario $$s || fail=1; \
	done; \
	exit $$fail

test-database:
	@mkdir -p bin
	timeout $(TIMEOUT) $(GODOT) $(RUNNER) --project games/database_test.rpgc --list-database --output bin/db_summary.json >/dev/null
	diff games/database_test_expected.json bin/db_summary.json && echo "database summary OK"

run-scenario:
	timeout $(TIMEOUT) $(GODOT) $(RUNNER) --scenario $(S)

list-maps:
	$(GODOT) $(RUNNER) --project $(P) --list-maps

list-database:
	$(GODOT) $(RUNNER) --project $(P) --list-database
