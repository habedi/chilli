# Generic Makefile for Zig projects

# Load environment variables from .env file
ifneq (,$(wildcard ./.env))
    include .env
    export $(shell sed 's/=.*//' .env)
else
    $(warning .env file not found. Environment variables not loaded.)
endif

################################################################################
# Configuration and Variables
################################################################################
ZIG           ?= zig
ZIG_VERSION   := $(shell $(ZIG) version)
BUILD_TYPE    ?= Debug
BUILD_OPTS      = -Doptimize=$(BUILD_TYPE)
JOBS          ?= $(shell nproc || echo 2)
SRC_DIR       := src
TEST_DIR      := tests
BUILD_DIR     := zig-out
CACHE_DIR     := .zig-cache
DOC_SRC       := src/root.zig
DOC_OUT       := docs/api/
COVERAGE_DIR  := coverage
BINARY_NAME   := template-zig-project
BINARY_PATH   := $(BUILD_DIR)/bin/$(BINARY_NAME)
TEST_EXECUTABLE := $(BUILD_DIR)/bin/test
PREFIX        ?= /usr/local
RELEASE_MODE := ReleaseSmall

SHELL         := /usr/bin/env bash
.SHELLFLAGS   := -eu -o pipefail -c

################################################################################
# Targets
################################################################################

.PHONY: all build rebuild run test cov lint format doc clean install-deps release help coverage
.DEFAULT_GOAL := help

help: ## Show the help messages for all targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

all: build test lint doc  ## build, test, lint, and doc

build: ## Build project (Mode=$(BUILD_TYPE))
	@echo "Building project in $(BUILD_TYPE) mode with $(JOBS) concurrent jobs..."
	$(ZIG) build $(BUILD_OPTS) -j$(JOBS)

rebuild: clean build  ## clean and build

run: build  ## Run the main application
	@echo "Running $(BINARY_NAME)..."
	$(ZIG) build run $(BUILD_OPTS) --

test: ## Run tests and generate coverage data
	@echo "Running tests with coverage enabled..."
	$(ZIG) build test $(BUILD_OPTS) -Denable-coverage=true -j$(JOBS)

release: ## Build in Release mode
	@echo "Building the project in Release mode..."
	@$(MAKE) BUILD_TYPE=$(RELEASE_MODE) build

clean: ## Remove docs, build artifacts, and cache directories
	@echo "Removing build artifacts, cache, generated docs, and coverage files..."
	rm -rf $(BUILD_DIR) $(CACHE_DIR) $(DOC_OUT) *.profraw $(COVERAGE_DIR)

lint: ## Check code style and formatting of Zig files
	@echo "Running code style checks..."
	$(ZIG) fmt --check $(SRC_DIR) $(TEST_DIR)

format: ## Format Zig files
	@echo "Formatting Zig files..."
	$(ZIG) fmt .

doc: ## Generate API documentation
	@echo "Generating documentation from $(DOC_SRC) to $(DOC_OUT)..."
	mkdir -p $(DOC_OUT)
	@if $(ZIG) doc --help > /dev/null 2>&1; then \
	  $(ZIG) doc $(DOC_SRC) --output-dir $(DOC_OUT); \
	else \
	  $(ZIG) test -femit-docs $(DOC_SRC); \
	  for f in docs/*; do \
		base=$$(basename "$$f"); \
		if [ "$$base" = "assets" ] || [ "$$base" = "api" ]; then \
		  continue; \
		fi; \
		mv "$$f" $(DOC_OUT)/; \
	  done; \
	fi

install-deps: ## Install system dependencies (for Debian-based systems)
	@echo "Installing system dependencies..."
	sudo apt-get update
	sudo apt-get install -y make llvm snapd
	sudo snap install zig  --beta --classic # Use `--edge --classic` to install the latest version

coverage: ## Generate code coverage report
	@echo "Building tests with coverage instrumentation..."
	@zig build test -Denable-coverage=true
	@echo "Generating coverage report..."
	@kcov --include-pattern=src --verify coverage-out zig-out/bin/test-root
