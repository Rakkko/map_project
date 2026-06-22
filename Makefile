###############################################################################
# OpenMapTiles + Martin Build Automation
###############################################################################

SHELL := /bin/bash
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

###############################################################################
# Variables
###############################################################################

OPENMAPTILES_DIR := ./host/openmaptiles

MARTIN_IMAGE := ghcr.io/maplibre/martin:latest
NGINX_IMAGE  := nginx:alpine

MARTIN_TAR := ./client/docker_image/martin.tar
NGINX_TAR  := ./client/docker_image/nginx.tar

MBTILES_OUTPUT := ./client/martin/area.mbtiles

###############################################################################
# Help Message
###############################################################################

define HELP_MESSAGE
===============================================================================
OpenMapTiles + Martin Build Automation

Usage:
  make <target> [arguments]

Targets:

  help
      Display this help message.

  all
      Initialize OpenMapTiles workspace, download required Docker images,
      and prepare font assets for Martin.

  set-max-zoom zoom_level=<ZOOM_LEVEL>
      Configure the maximum tile zoom level for OpenMapTiles and Martin.

  download-data area=<AREA> [zoom_level=<ZOOM_LEVEL>]
      Download OSM data, import required datasets, and generate MBTiles.

  pbf-to-mbtiles area=<AREA> [zoom_level=<ZOOM_LEVEL>] [download=true]
      Generate MBTiles from an existing PBF file.
      If download=true, Wikidata will also be downloaded and imported.

  publish-mbtiles
      Start Martin and Nginx services and publish generated MBTiles.

  stop
      Stop all running services.

Examples:

  make all

  make download-data area=china

  make download-data area=china zoom_level=12

  make pbf-to-mbtiles area=china

  make pbf-to-mbtiles area=china download=true

===============================================================================
endef

export HELP_MESSAGE

###############################################################################
# Utility Targets
###############################################################################

.PHONY: help
help:
	@echo "$$HELP_MESSAGE"

.PHONY: check-openmaptiles
check-openmaptiles:
	@test -d "$(OPENMAPTILES_DIR)" || \
	( echo "ERROR: OpenMapTiles workspace not initialized. Run 'make all' first."; exit 1 )

.PHONY: prepare-images
prepare-images:
	@mkdir -p ./client/docker_image

	@echo "Pulling Martin image..."
	@docker pull $(MARTIN_IMAGE)

	@echo "Pulling Nginx image..."
	@docker pull $(NGINX_IMAGE)

	@echo "Saving images..."
	@docker save $(MARTIN_IMAGE) -o $(MARTIN_TAR)
	@docker save $(NGINX_IMAGE) -o $(NGINX_TAR)

.PHONY: prepare-openmaptiles
prepare-openmaptiles:
	@mkdir -p host

	@if [ -d "$(OPENMAPTILES_DIR)/.git" ]; then \
		echo "Updating OpenMapTiles repository..."; \
		git -C $(OPENMAPTILES_DIR) pull; \
	else \
		echo "Cloning OpenMapTiles repository..."; \
		git clone https://github.com/openmaptiles/openmaptiles.git $(OPENMAPTILES_DIR); \
	fi

	@$(MAKE) -C $(OPENMAPTILES_DIR) download-fonts

	@rm -rf ./client/frontend/glyphs
	@mkdir -p ./client/frontend/glyphs

	@cp -R \
		$(OPENMAPTILES_DIR)/data/fonts/* \
		./client/frontend/glyphs/

###############################################################################
# Main Initialization
###############################################################################

.PHONY: all
all: prepare-images prepare-openmaptiles

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

###############################################################################
# Shared Tile Generation Workflow
###############################################################################

define GENERATE_MBTILES_WORKFLOW
set -e; \
trap '$(MAKE) -C $(OPENMAPTILES_DIR) stop-db >/dev/null 2>&1 || true' EXIT; \
\
$(MAKE) -C $(OPENMAPTILES_DIR) clean; \
$(MAKE) -C $(OPENMAPTILES_DIR); \
$(MAKE) -C $(OPENMAPTILES_DIR) start-db; \
$(MAKE) -C $(OPENMAPTILES_DIR) import-data;
\
$(1) \
\
$(MAKE) -C $(OPENMAPTILES_DIR) import-sql area=$(area); \
$(MAKE) -C $(OPENMAPTILES_DIR) generate-bbox-file area=$(area); \
$(MAKE) -C $(OPENMAPTILES_DIR) generate-tiles-pg area=$(area); \
\
cp -f \
	$(OPENMAPTILES_DIR)/data/tiles.mbtiles \
	$(MBTILES_OUTPUT); \
\
echo "MBTiles generated successfully:"; \
echo "  $(MBTILES_OUTPUT)"
endef

###############################################################################
# Download and Build
###############################################################################

.PHONY: download-data
download-data: check-openmaptiles

ifndef area
	$(error area is required. Usage: make download-data area=<AREA>)
endif

ifdef zoom_level
	@$(MAKE) set-max-zoom zoom_level=$(zoom_level)
endif

	@$(call GENERATE_MBTILES_WORKFLOW,\
	$(MAKE) -C $(OPENMAPTILES_DIR) download area=$(area); \
	$(MAKE) -C $(OPENMAPTILES_DIR) import-osm area=$(area); \
	$(MAKE) -C $(OPENMAPTILES_DIR) import-wikidata area=$(area);)

###############################################################################
# Existing PBF -> MBTiles
###############################################################################

.PHONY: pbf-to-mbtiles
pbf-to-mbtiles: check-openmaptiles

ifndef area
	$(error area is required. Usage: make pbf-to-mbtiles area=<AREA>)
endif

ifdef zoom_level
	@$(MAKE) set-max-zoom zoom_level=$(zoom_level)
endif

	@$(call GENERATE_MBTILES_WORKFLOW,\
	$(MAKE) -C $(OPENMAPTILES_DIR) import-osm area=$(area); \
	$(if $(filter true,$(download)),\
	$(MAKE) -C $(OPENMAPTILES_DIR) import-wikidata area=$(area);,))

###############################################################################
# Publish Services
###############################################################################

.PHONY: publish-mbtiles
publish-mbtiles:

	@test -f $(MBTILES_OUTPUT) || \
	( echo "ERROR: MBTiles file not found. Generate it first."; exit 1 )

	@cd ./client && docker compose down

	@if ! docker image inspect $(MARTIN_IMAGE) >/dev/null 2>&1; then \
		docker load -i $(MARTIN_TAR); \
	fi

	@if ! docker image inspect $(NGINX_IMAGE) >/dev/null 2>&1; then \
		docker load -i $(NGINX_TAR); \
	fi

	@test -f ./client/frontend/styles/style-martin_mbtiles.json
	@test -f ./client/martin/config_mbtiles.yaml

	@cp \
		./client/frontend/styles/style-martin_mbtiles.json \
		./client/frontend/styles/style-martin.json

	@cp \
		./client/martin/config_mbtiles.yaml \
		./client/martin/config.yaml

	@cd ./client && docker compose up -d

	@echo "Martin service started."

###############################################################################
# Stop Services
###############################################################################

.PHONY: stop
stop:
	@cd ./client && docker compose down
	@echo "Services stopped."