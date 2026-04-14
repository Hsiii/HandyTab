.PHONY: all clean app dmg build

PYTHON = ./venv/bin/python3
APP_NAME = HandyTab
DIST_DIR = dist
BUILD_DIR = build
APP_BUNDLE = $(DIST_DIR)/$(APP_NAME).app
DMG_FILE = $(DIST_DIR)/$(APP_NAME).dmg

all: build

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)

app:
	$(PYTHON) setup.py py2app

dmg: app
	@echo "Creating DMG..."
	mkdir -p $(DIST_DIR)/dmg_root
	cp -R $(APP_BUNDLE) $(DIST_DIR)/dmg_root/
	ln -s /Applications $(DIST_DIR)/dmg_root/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(DIST_DIR)/dmg_root -ov -format UDZO $(DMG_FILE)
	rm -rf $(DIST_DIR)/dmg_root
	@echo "DMG created at $(DMG_FILE)"

build: clean dmg
