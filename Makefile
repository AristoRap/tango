LLVM_CONFIG ?= $(shell command -v llvm-config 2>/dev/null || command -v /opt/homebrew/opt/llvm/bin/llvm-config 2>/dev/null)
CRYSTAL_CACHE_DIR ?= $(CURDIR)/.crystal-cache
CRYSTAL_PATH ?= $(shell crystal env CRYSTAL_PATH)

CRYSTAL_ENV = LLVM_CONFIG=$(LLVM_CONFIG) CRYSTAL_CACHE_DIR=$(CRYSTAL_CACHE_DIR) CRYSTAL_PATH=$(CRYSTAL_PATH)
CHANGED_CRYSTAL_SOURCES = $(shell git diff --name-only --diff-filter=ACMR -- '*.cr' | sort)
UNTRACKED_CRYSTAL_SOURCES = $(shell git ls-files --others --exclude-standard -- '*.cr' | sort)
CRYSTAL_SOURCES = $(sort $(CHANGED_CRYSTAL_SOURCES) $(UNTRACKED_CRYSTAL_SOURCES))
TRACKED_CRYSTAL_SOURCES = $(shell git ls-files -- '*.cr' | sort)
SEED ?= 1
N ?= 400


.PHONY: ci spec audit fuzz build build-release release format format-check format-check-all clean-cache clean-work

ci: format-check-all spec build-release
	./bin/tango doctor

spec:
	env $(CRYSTAL_ENV) crystal spec

audit:
	env $(CRYSTAL_ENV) crystal spec spec/duplication_guardrails_spec.cr

fuzz:
	python3 scripts/fuzz.py $(SEED) $(N)

build:
	env $(CRYSTAL_ENV) shards build tango

build-release:
	env $(CRYSTAL_ENV) shards build --release tango

release: build-release
	rm -f /usr/local/bin/tango
	cp ./bin/tango /usr/local/bin/tango

format:
	@if [ -n "$(CRYSTAL_SOURCES)" ]; then env $(CRYSTAL_ENV) crystal tool format $(CRYSTAL_SOURCES); fi

format-check:
	@if [ -n "$(CRYSTAL_SOURCES)" ]; then env $(CRYSTAL_ENV) crystal tool format --check $(CRYSTAL_SOURCES); fi

format-check-all:
	@env $(CRYSTAL_ENV) crystal tool format --check $(TRACKED_CRYSTAL_SOURCES)

clean-cache:
	rm -rf $(CRYSTAL_CACHE_DIR)

clean-work:
	rm -rf .tango
