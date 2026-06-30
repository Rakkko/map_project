################################################################################
# Makefile
################################################################################

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

.DEFAULT_GOAL := help

###############################################################################
# Platform Compatibility
###############################################################################

UNAME := $(shell uname)

ifeq ($(UNAME),Darwin)
SED_INPLACE := sed -i ''
else
SED_INPLACE := sed -i
endif

################################################################################
# Variables
################################################################################

area ?= tiles

CLIENT_DIR := client
HOST_DIR := host

IMAGE_CACHE := $(CLIENT_DIR)/docker_image

MARTIN_DIR := $(CLIENT_DIR)/martin

OPENMAPTILES_DIR := $(HOST_DIR)/openmaptiles

COMPOSE_FILE := $(CLIENT_DIR)/docker-compose.yml

MARTIN_IMAGE := ghcr.io/maplibre/martin:latest
NGINX_IMAGE := nginx:alpine

MARTIN_TAR := $(IMAGE_CACHE)/martin.tar
NGINX_TAR := $(IMAGE_CACHE)/nginx.tar

################################################################################

.PHONY: \
help init \
publish-mbtiles online-publish offline-publish \
check-env check-init check-images check-cache check-openmaptiles \
check-tools check-docker check-git check-make \
clean stop restart

################################################################################
# Help
################################################################################

help:
	@echo ""
	@echo "Available targets:"
	@echo ""
	@echo "  make init"
	@echo "      Initialize environment."
	@echo ""
	@echo "  make set-max-zoom zoom_level=<ZOOM_LEVEL>"
	@echo "      Set max zoom level for OpenMapTiles."
	@echo ""
	@echo "  make publish-mbtiles area=<AREA>"
	@echo "      Publish existing mbtiles."
	@echo ""
	@echo "  make online-publish area=<AREA>"
	@echo "      Generate mbtiles online."
	@echo ""
	@echo "  make offline-publish area=<AREA>"
	@echo "      Generate mbtiles from local osm.pbf."
	@echo ""
	@echo "  make stop"
	@echo "      Stop martin/nginx."
	@echo ""
	@echo "  make restart"
	@echo "      Restart martin/nginx."
	@echo ""
	@echo "  make clean"
	@echo "      Remove generated mbtiles."
	@echo ""

################################################################################
# Basic Checks
################################################################################

check-docker:
	@command -v docker >/dev/null || \
		{ echo "ERROR: docker not installed."; exit 1; }

check-git:
	@command -v git >/dev/null || \
		{ echo "ERROR: git not installed."; exit 1; }

check-make:
	@command -v make >/dev/null || \
		{ echo "ERROR: make not installed."; exit 1; }

check-tools: check-docker check-git check-make

################################################################################

check-openmaptiles:
	@if [ ! -d "$(OPENMAPTILES_DIR)" ]; then \
		echo "ERROR: openmaptiles not initialized."; \
		exit 1; \
	fi

################################################################################

check-init: check-tools check-openmaptiles

################################################################################

check-images:

	@if ! docker image inspect "$(MARTIN_IMAGE)" >/dev/null 2>&1; then \
		if [ -f "$(MARTIN_TAR)" ]; then \
			echo "Loading Martin image..."; \
			docker load -i "$(MARTIN_TAR)"; \
		else \
			echo "ERROR: Martin image missing."; \
			exit 1; \
		fi; \
	fi

	@if ! docker image inspect "$(NGINX_IMAGE)" >/dev/null 2>&1; then \
		if [ -f "$(NGINX_TAR)" ]; then \
			echo "Loading nginx image..."; \
			docker load -i "$(NGINX_TAR)"; \
		else \
			echo "ERROR: nginx image missing."; \
			exit 1; \
		fi; \
	fi

################################################################################
# Init
################################################################################

init: check-tools

	@mkdir -p $(IMAGE_CACHE)

	@echo "Checking Martin image..."
	@if ! docker image inspect "$(MARTIN_IMAGE)" >/dev/null 2>&1; then \
		docker pull $(MARTIN_IMAGE); \
	fi

	@echo "Checking nginx image..."
	@if ! docker image inspect "$(NGINX_IMAGE)" >/dev/null 2>&1; then \
		docker pull $(NGINX_IMAGE); \
	fi

	@echo "Saving docker images..."
	@docker save $(MARTIN_IMAGE) -o $(MARTIN_TAR)
	@docker save $(NGINX_IMAGE) -o $(NGINX_TAR)

	@if [ ! -d "$(OPENMAPTILES_DIR)" ]; then \
		echo "Cloning OpenMapTiles..."; \
		git clone https://github.com/openmaptiles/openmaptiles.git $(OPENMAPTILES_DIR); \
	else \
		echo "Updating OpenMapTiles..."; \
		cd $(OPENMAPTILES_DIR) && git pull; \
	fi

	@echo ""
	@echo "Initialization completed."

###############################################################################
# Zoom Configuration
###############################################################################

.PHONY: set-max-zoom
set-max-zoom: check-openmaptiles
ifndef zoom_level
	$(error zoom_level is required. Usage: make set-max-zoom zoom_level=<ZOOM_LEVEL>)
endif
	@echo "Setting max zoom level to $(zoom_level)..."

	@$(SED_INPLACE) \
		"s/^MAX_ZOOM=.*/MAX_ZOOM=$(zoom_level)/" \
		$(OPENMAPTILES_DIR)/.env

	@$(SED_INPLACE) \
		"s/maxzoom: .*/maxzoom: $(zoom_level)/" \
		$(OPENMAPTILES_DIR)/openmaptiles.yaml

################################################################################
# Publish Existing MBTiles
################################################################################

publish-mbtiles: check-init check-images

	@if [ ! -f "$(MARTIN_DIR)/$(area).mbtiles" ]; then \
		echo "ERROR: $(area).mbtiles not found."; \
		exit 1; \
	fi

	@cp \
		./client/frontend/styles/style_mbtiles.json \
		./client/frontend/styles/style.json

	@cp \
		./client/martin/config_mbtiles.yaml \
		./client/martin/config.yaml

	@if docker compose -f $(COMPOSE_FILE) ps martin | grep Up >/dev/null 2>&1; then \
		echo "Restart Martin..."; \
		AREA=$(area) docker compose -f $(COMPOSE_FILE) restart martin; \
	else \
		echo "Starting services..."; \
		AREA=$(area) docker compose -f $(COMPOSE_FILE) up -d; \
	fi

	@echo ""
	@echo "Published $(area).mbtiles"

################################################################################
# Online Publish
################################################################################

online-publish: check-init

	@cd $(OPENMAPTILES_DIR) && \
	make clean && \
	make && \
	make start-db && \
	make import-data && \
	make download area=$(area) && \
	make import-osm area=$(area) && \
	make import-wikidata area=$(area) && \
	make import-sql && \
	make generate-bbox-file area=$(area) && \
	make generate-tiles-pg area=$(area)

	@cp $(OPENMAPTILES_DIR)/data/tiles.mbtiles \
		$(MARTIN_DIR)/$(area).mbtiles

	@$(MAKE) publish-mbtiles area=$(area)

################################################################################
# Offline Publish
################################################################################

offline-publish: check-init

	@if [ ! -f "$(OPENMAPTILES_DIR)/data/$(area).osm.pbf" ]; then \
		echo "ERROR: $(area).osm.pbf not found."; \
		exit 1; \
	fi

	@cd $(OPENMAPTILES_DIR) && \
	make clean && \
	make && \
	make start-db && \
	make import-data && \
	make import-osm area=$(area) && \

	@cd $(OPENMAPTILES_DIR) && \
	if ! make import-wikidata area=$(AREA); then \
		echo ""; \
		echo "ERROR: Wikidata cache is not available."; \
		echo "The required Wikidata resources have not been cached locally."; \
		echo "Please connect to the Internet and run 'make import-wikidata area=$(AREA)' once before using offline publishing."; \
		exit 1; \
	fi

	@cd $(OPENMAPTILES_DIR) && \
	make import-sql && \
	make generate-bbox-file area=$(area) && \
	make generate-tiles-pg area=$(area)

	@cp $(OPENMAPTILES_DIR)/data/tiles.mbtiles \
		$(MARTIN_DIR)/$(area).mbtiles

	@$(MAKE) publish-mbtiles area=$(area)

################################################################################
# Stop
################################################################################

stop:
	@docker compose -f $(COMPOSE_FILE) down

################################################################################
# Restart
################################################################################

restart:
	@docker compose -f $(COMPOSE_FILE) restart

################################################################################
# Clean
################################################################################

clean:

	@find $(MARTIN_DIR) -name "*.mbtiles" -delete

	@echo "Clean completed."

################################################################################