metadata = $(shell sed -n 's/.*"$(1)": "\(.*\)".*/\1/p' src/metadata.json)

UUID := $(call metadata,uuid)
VERSION := $(call metadata,version-name)
ZIP := dist/$(UUID).shell-extension.zip
SOURCES := src/metadata.json src/extension.js src/prefs.js $(wildcard src/schemas/*.gschema.xml)

.PHONY: pack checksum install uninstall lint e2e tag clean

pack: $(ZIP)

$(ZIP): $(SOURCES)
	glib-compile-schemas --strict --dry-run src/schemas
	mkdir -p dist
	rm -f $@
	cd src && zip -qX ../$@ $(SOURCES:src/%=%)

checksum: $(ZIP)
	cd dist && sha256sum $(notdir $(ZIP)) > $(notdir $(ZIP)).sha256

install: $(ZIP)
	gnome-extensions install --force $(ZIP)

uninstall:
	gnome-extensions uninstall $(UUID)

lint:
	node --check src/extension.js
	node --check src/prefs.js
	bash -n tests/e2e.sh

e2e:
	@test -n "$(TARGET)" || { echo 'Set TARGET to local or an SSH destination, for example: make e2e TARGET=user@host' >&2; exit 2; }
	tests/e2e.sh $(TARGET)

tag: lint
	@echo '$(VERSION)' | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$$' || { echo 'version-name in src/metadata.json must use MAJOR.MINOR.PATCH.' >&2; exit 1; }
	@test "$$(git branch --show-current)" = main || { echo 'Create release tags from main.' >&2; exit 1; }
	@test -z "$$(git status --porcelain)" || { echo 'Commit all changes before you create a release tag.' >&2; exit 1; }
	@! git rev-parse -q --verify 'refs/tags/v$(VERSION)' >/dev/null || { echo 'Tag v$(VERSION) already exists.' >&2; exit 1; }
	git tag --annotate v$(VERSION) --message='Release $(VERSION)'

clean:
	rm -rf dist
