# Copyright (C) 2021 Monocle authors
# SPDX-License-Identifier: AGPL-3.0-or-later

MESSAGES = monocle/config.proto monocle/task_data.proto

codegen: codegen-python codegen-javascript codegen-stubs codegen-openapi

codegen-stubs:
	mkdir -p srcgen/
	(cd codegen; cabal run monocle-codegen ../protos/monocle/http.proto ../monocle/webapi.py ../srcgen/WebApi.res)
	black ./monocle/webapi.py
	./web/node_modules/.bin/bsc -format ./srcgen/WebApi.res > ./web/src/components/WebApi.res
	rm -Rf srcgen/

codegen-python:
	protoc -I=./protos/ --python_out=./monocle/messages --mypy_out=./monocle/messages $(MESSAGES)
	mv monocle/messages/monocle/* monocle/messages/
	black monocle/messages/*.py*
	rm -Rf monocle/messages/monocle

codegen-javascript:
	rm -f web/src/messages/*
	sh -c 'for pb in $(MESSAGES); do ocaml-protoc -bs -ml_out web/src/messages/ protos/$${pb}; done'
	python3 ./codegen/rename_bs_module.py ./web/src/messages/

codegen-openapi:
	protoc -I=./protos/ -I/usr/src/ -I../../googleapis/googleapis/ --openapi_out=./doc/ monocle/http.proto
	@echo Created doc/openapi.yaml

codegen-with-container:
	podman run -it -v $(shell pwd):/data:z --rm changemetrics/monocle_codegen make
	@echo Success.