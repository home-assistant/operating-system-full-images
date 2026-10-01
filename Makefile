# HAOS Full Image Builder - Host Makefile
# Runs the builder container

IMAGE_NAME ?= haos-full-builder
INPUT_DIR ?= $(CURDIR)/input
OUTPUT_DIR ?= $(CURDIR)/output
CACHE_DIR ?= $(CURDIR)/cache
CHANNEL ?= stable

DOCKER_RUN = docker run --rm --privileged \
	-v "$(INPUT_DIR):/input" \
	-v "$(OUTPUT_DIR):/output" \
	-v "$(CACHE_DIR):/cache" \
	-e CHANNEL=$(CHANNEL) \
	$(if $(VERSION_FILE),-e VERSION_FILE=$(VERSION_FILE)) \
	$(if $(DIND_IMAGE),-e DIND_IMAGE=$(DIND_IMAGE)) \
	-e HOST_UID=$(shell id -u) \
	-e HOST_GID=$(shell id -g) \
	-e LOG_COLOR=1 \
	$(IMAGE_NAME)

.PHONY: help docker-image build build-all fetch clean shell

help:
	@echo "HAOS Full Image Builder"
	@echo ""
	@echo "Host targets:"
	@echo "  make docker-image          Build the builder container"
	@echo "  make build IMAGE=<file>    Build a single full image"
	@echo "  make build-all             Build all images in input/"
	@echo "  make fetch BOARD=<b>       Fetch containers for board"
	@echo "  make clean                 Clean work directory"
	@echo "  make shell                 Interactive shell in container"
	@echo ""
	@echo "Options:"
	@echo "  IMAGE=<file>       Input image filename (e.g., haos_green-17.0.img.xz)"
	@echo "  BOARD=<name>       Board name (e.g., green, ova)"
	@echo "  CHANNEL=<channel>  Version channel: stable, beta, dev (default: stable)"
	@echo "  VERSION_FILE=<src> Custom version JSON (URL or /input path) overriding CHANNEL's"

docker-image:
	docker build -t $(IMAGE_NAME) $(if $(DIND_IMAGE),--build-arg DIND_IMAGE=$(DIND_IMAGE)) .

build:
ifndef IMAGE
	$(error IMAGE is required. Usage: make build IMAGE=<filename>)
endif
	@mkdir -p "$(INPUT_DIR)" "$(OUTPUT_DIR)" "$(CACHE_DIR)"
	$(DOCKER_RUN) build IMAGE=/input/$(IMAGE)

build-all:
	@mkdir -p "$(INPUT_DIR)" "$(OUTPUT_DIR)" "$(CACHE_DIR)"
	$(DOCKER_RUN) build-all

fetch:
ifndef BOARD
	$(error BOARD is required. Usage: make fetch BOARD=<board>)
endif
	@mkdir -p "$(CACHE_DIR)"
	$(DOCKER_RUN) fetch-containers BOARD=$(BOARD)

clean:
	$(DOCKER_RUN) clean-all

shell:
	@mkdir -p "$(INPUT_DIR)" "$(OUTPUT_DIR)" "$(CACHE_DIR)"
	docker run --rm -it --privileged \
		-v "$(INPUT_DIR):/input" \
		-v "$(OUTPUT_DIR):/output" \
		-v "$(CACHE_DIR):/cache" \
		-e LOG_COLOR=1 \
		--entrypoint /bin/bash \
		$(IMAGE_NAME)
