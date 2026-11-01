PREFIX ?= $(HOME)/.local
BATS ?= $(shell command -v bats 2>/dev/null || echo tests/vendor/bats-core/bin/bats)
SHELLCHECK ?= shellcheck
SHFMT ?= shfmt
SOURCES := bin/gitctl $(wildcard lib/*/*.sh) install.sh

.PHONY: test lint fmt install uninstall deps check

test: ## Ejecuta los tests (bats)
	$(BATS) tests/

lint: ## shellcheck + comprobación de formato
	$(SHELLCHECK) -x $(SOURCES)
	$(SHFMT) -d $(SOURCES)

fmt: ## Formatea el código
	$(SHFMT) -w $(SOURCES)

check: lint test

deps: ## Descarga bats-core en tests/vendor si no está instalado
	@test -x tests/vendor/bats-core/bin/bats || git clone -q --depth 1 https://github.com/bats-core/bats-core tests/vendor/bats-core

install: ## Instala un enlace en $(PREFIX)/bin
	./install.sh --prefix "$(PREFIX)"

uninstall:
	./install.sh --prefix "$(PREFIX)" --uninstall
