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
	docker save ghcr.io/maplibre/martin:latest ./client/docker_image/martin.tar
	docker save nginx:alpine ./client/docker_image/nginx.tar
	cd ./host
	git clone https://github.com/openmaptiles/openmaptiles.git
	cd ./openmaptiles
	make download-fonts
	mv ./data/fonts ../../client/frontend/glyphs

.PHONY: help
help:
	@echo "$$HELP_MESSAGE"

.PHONY: download-data
download-data:
ifndef area
	$(error area is required, usage: make download-data area=china)
endif
	cd ./host/openmaptiles
	make clean
	make
	make start-db
	make import-data
	make download area=$(area)
	make import-osm area=$(area)
	make import-wikidata area=$(area)
	make import-sql area=$(area)
	make generate-bbox-file area=$(area)
	make generate-tiles-pg area=$(area)
	make stop-db

.PHONY: pbf-to-mbtiles
pbf-to-mbtiles:
ifndef area
	$(error area is required, usage: make pbf-to-mbtiles area=china)
endif
	make import-osm area=$(area)
ifeq ($(download),true)
	make import-wikidata area=$(area)
endif
	make import-sql area=$(area)
	make generate-bbox-file area=$(area)
	make generate-tiles-pg area=$(area)
	make stop-db

.PHONY: publish-mbtiles
publish-mbtiles:
	docker compose down
	docker load -i ./client/docker_image/martin.tar
	docker load -i ./client/docker_image/nginx.tar
	cp ./frontend/styles/style-martin_publish-mbtiles.json ./frontend/styles/style-martin.json
	cp ./martin/config_publish-mbtiles.yaml ./martin/config.yaml
	docker compose up -d

.PHONY: stop
stop:
	docker compose down