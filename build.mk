# HAOS Full Image Builder - Makefile
# Build orchestration and entry point

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c

SCRIPT_DIR := /opt/haos-builder/scripts

# Directories - available in scripts
export WORK_DIR ?= /work
export INPUT_DIR ?= /input
export OUTPUT_DIR ?= /output
export CACHE_DIR ?= /cache

# Configuration
CHANNEL ?= stable

# Find input images
INPUT_IMAGES := $(wildcard $(INPUT_DIR)/haos_*.img.xz $(INPUT_DIR)/haos_*.qcow2.xz)

.PHONY: help build build-all fetch-containers clean clean-all extract prepare analyze split extract-data create-data reassemble

# Default target
help:
	@echo "HAOS Full Image Builder"
	@echo ""
	@echo "Usage:"
	@echo "  make build IMAGE=<path>    Build a single full image"
	@echo "  make build-all             Build all images in INPUT_DIR"
	@echo "  make fetch-containers      Fetch container images for a board"
	@echo "  make clean                 Clean work directory"
	@echo "  make clean-all             Clean work and output directories"
	@echo ""
	@echo "Options:"
	@echo "  IMAGE=<path>               Path to HAOS image (*.img.xz or *.qcow2.xz)"
	@echo "  CHANNEL=<channel>          Version channel: stable, beta, dev (default: stable)"
	@echo "  VERSION_FILE=<src>         Custom version JSON (URL or path) overriding CHANNEL's"
	@echo ""
	@echo "Found input images:"
	@for img in $(INPUT_IMAGES); do echo "  - $$img"; done

# Build a single image
build:
ifndef IMAGE
	$(error IMAGE is required. Usage: make build IMAGE=<path>)
endif
	@echo "Building full image from: $(IMAGE)"
	@$(MAKE) _build-image IMAGE="$(IMAGE)"

# Build all images
build-all:
	@if [ -z "$(INPUT_IMAGES)" ]; then \
		echo "No input images found in $(INPUT_DIR)"; \
		exit 1; \
	fi
	@for img in $(INPUT_IMAGES); do \
		echo "=== Building: $$img ==="; \
		$(MAKE) _build-image IMAGE="$$img" || exit 1; \
	done
	@echo "=== All builds complete ==="

# Internal build target
_build-image:
	@# Extract board and version from filename
	$(eval BOARD := $(shell bash -c 'source $(SCRIPT_DIR)/lib.sh && get_board_from_filename "$(IMAGE)"'))
	$(eval VERSION := $(shell bash -c 'source $(SCRIPT_DIR)/lib.sh && get_version_from_filename "$(IMAGE)"'))
	$(eval ARCH := $(shell bash -c 'source $(SCRIPT_DIR)/lib.sh && get_arch "$(BOARD)"'))
	$(eval MACHINE := $(shell bash -c 'source $(SCRIPT_DIR)/lib.sh && get_machine "$(BOARD)"'))
	@echo "Board: $(BOARD), Version: $(VERSION), Arch: $(ARCH), Machine: $(MACHINE), Channel: $(CHANNEL)"
	@# Clean work directory for fresh build
	@rm -rf "$(WORK_DIR)"/*
	@mkdir -p "$(WORK_DIR)/original"
	@# Prepare image and analyze partitions
	$(SCRIPT_DIR)/prepare.sh "$(IMAGE)"
	@# Analyze partitions
	$(SCRIPT_DIR)/analyze.sh
	@# Split partitions
	$(SCRIPT_DIR)/split.sh "$(BOARD)"
	@# Extract data partition contents
	$(SCRIPT_DIR)/extract-data.sh
	@# Fetch containers
	$(SCRIPT_DIR)/fetch-containers.sh "$(BOARD)" "$(CHANNEL)"
	@# Create new data partition
	$(SCRIPT_DIR)/create-data.sh "$(BOARD)" "$(CHANNEL)"
	@# Reassemble image
	$(SCRIPT_DIR)/reassemble.sh "$(BOARD)" "$(VERSION)"
	@echo "Build complete for $(BOARD)-$(VERSION)"

# Fetch containers for a board
fetch-containers:
ifndef BOARD
	$(error BOARD is required. Usage: make fetch-containers BOARD=<board>)
endif
	$(SCRIPT_DIR)/fetch-containers.sh "$(BOARD)" "$(CHANNEL)"

# Clean work directory
clean:
	rm -rf "$(WORK_DIR)"/*

# Clean everything
clean-all: clean
	rm -rf "$(OUTPUT_DIR)"/*
	rm -rf "$(CACHE_DIR)"/*

extract:
ifndef IMAGE
	$(error IMAGE is required)
endif
	$(SCRIPT_DIR)/extract-data.sh "$(IMAGE)"

prepare:
ifndef IMAGE
	$(error IMAGE is required)
endif
	$(SCRIPT_DIR)/prepare.sh "$(IMAGE)"

analyze:
	$(SCRIPT_DIR)/analyze.sh

split:
ifndef BOARD
	$(error BOARD is required)
endif
	$(SCRIPT_DIR)/split.sh "$(BOARD)"

extract-data:
	$(SCRIPT_DIR)/extract-data.sh

create-data:
ifndef BOARD
	$(error BOARD is required)
endif
	$(SCRIPT_DIR)/create-data.sh "$(BOARD)" "$(CHANNEL)"

reassemble:
ifndef BOARD
	$(error BOARD is required)
endif
ifndef VERSION
	$(error VERSION is required)
endif
	$(SCRIPT_DIR)/reassemble.sh "$(BOARD)" "$(VERSION)"
