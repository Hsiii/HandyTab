.PHONY: all build run dmg clean

all: build

build:
	swift build

run:
	swift run

dmg:
	./scripts/dmg.sh

clean:
	rm -rf .build build dist
