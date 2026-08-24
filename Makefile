EXEC     := WisperClone
CONFIG   ?= release
SCRATCH  := $(HOME)/Library/Caches/WisperCloneBuild/scratch
BUILD    := $(SCRATCH)/$(CONFIG)/$(EXEC)
STAGE    := $(HOME)/Library/Caches/WisperCloneBuild
APPNAME  := WisperClone.app
BUNDLE   := $(STAGE)/$(APPNAME)
CONTENTS := $(BUNDLE)/Contents

DEVELOPER_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
                  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')
APPLE_DEVELOPMENT_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
                          | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)".*/\1/')
SIGN_ID := $(or $(strip $(DEVELOPER_ID)),$(strip $(APPLE_DEVELOPMENT_ID)),-)

.PHONY: all build app run install clean icon

all: app

build:
	swift build -c $(CONFIG) --scratch-path "$(SCRATCH)"

icon:
	@swift Tools/makeicon.swift
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "Scritto Resources/AppIcon.icns"

app: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp $(BUILD) "$(CONTENTS)/MacOS/$(EXEC)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@cp Resources/AppIcon.icns "$(CONTENTS)/Resources/"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@xattr -cr "$(BUNDLE)"
	@codesign --force --sign "$(SIGN_ID)" \
		--entitlements Resources/$(EXEC).entitlements \
		--options runtime \
		--timestamp=none \
		"$(BUNDLE)"
	@echo "Creato $(BUNDLE)  [firma: $(SIGN_ID)]"

run: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@open "$(BUNDLE)"

install: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@rm -rf "/Applications/$(APPNAME)"
	@cp -R "$(BUNDLE)" "/Applications/$(APPNAME)"
	@open "/Applications/$(APPNAME)"
	@echo "Installato in /Applications/$(APPNAME)"

clean:
	@rm -rf .build "$(STAGE)" "$(SCRATCH)"
