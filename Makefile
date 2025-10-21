SHELL := /usr/bin/env bash

include tools/make/Makefile.validate

.PHONY: help
help:
	@echo "Available validation targets:"
	@printf '  %s\n' \
	  'make validate:repo' \
	  'make validate:tf:static' \
	  'make validate:tf:policy' \
	  'make validate:tf:plan-local' \
	  'make validate:cost' \
	  'make validate:k8s:local' \
	  'make validate:smoke:offline'
