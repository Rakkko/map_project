define HELP_MESSAGE
==============================================================================
Hints fo user:
  make
  make download-data area=china
  make pbf-to-mbtiles area=china [download=true / false]
  make publish-mbtiles
  make stop
==============================================================================
endef
export HELP_MESSAGE

.PHONY: all
all:
	docker pull ghcr.io/maplibre/martin:latest
	docker pull nginx:alpine
	mkdir -p client/docker_image
	docker save ghcr.io/maplibre/martin:latest -o ./client/docker_image/martin.tar
	docker save nginx:alpine -o ./client/docker_image/nginx.tar
	mkdir -p host
	cd ./host && git clone https://github.com/openmaptiles/openmaptiles.git
	cd ./host/openmaptiles && make download-fonts
	mv ./host/openmaptiles/data/fonts ./client/frontend/glyphs

.PHONY: help
help:
	@echo "$$HELP_MESSAGE"

.PHONY: download-data
download-data:
ifndef area
	$(error area is required, usage: make download-data area=china)
endif
	$(MAKE) -C host/openmaptiles clean
	$(MAKE) -C host/openmaptiles
	$(MAKE) -C host/openmaptiles start-db
	$(MAKE) -C host/openmaptiles import-data
	$(MAKE) -C host/openmaptiles download area=$(area)
	$(MAKE) -C host/openmaptiles import-osm area=$(area)
	$(MAKE) -C host/openmaptiles import-wikidata area=$(area)
	$(MAKE) -C host/openmaptiles import-sql area=$(area)
	$(MAKE) -C host/openmaptiles generate-bbox-file area=$(area)
	$(MAKE) -C host/openmaptiles generate-tiles-pg area=$(area)
	$(MAKE) -C host/openmaptiles stop-db
	cp -f ./host/openmaptiles/data/tiles.mbtiles ./client/martin/area.mbtiles

.PHONY: pbf-to-mbtiles
pbf-to-mbtiles:
ifndef area
	$(error area is required, usage: make pbf-to-mbtiles area=china)
endif
	$(MAKE) -C host/openmaptiles start-db
	$(MAKE) -C host/openmaptiles import-osm area=$(area)
ifeq ($(download),true)
	$(MAKE) -C host/openmaptiles import-wikidata area=$(area)
endif
	$(MAKE) -C host/openmaptiles import-sql area=$(area)
	$(MAKE) -C host/openmaptiles generate-bbox-file area=$(area)
	$(MAKE) -C host/openmaptiles generate-tiles-pg area=$(area)
	$(MAKE) -C host/openmaptiles stop-db

.PHONY: publish-mbtiles
publish-mbtiles:
	cd ./client && docker compose down
	docker load -i ./client/docker_image/martin.tar
	docker load -i ./client/docker_image/nginx.tar
	cp ./client/frontend/styles/style-martin_mbtiles.json ./client/frontend/styles/style-martin.json
	cp ./client/martin/config_mbtiles.yaml ./client/martin/config.yaml
	cd ./client && docker compose up -d

.PHONY: stop
stop:
	docker compose down