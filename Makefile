.PHONY: all build run dmg brew tap clean

all: build

build:
	swift build

run:
	swift run

dmg:
	./scripts/dmg.sh

brew:
	./scripts/brew.sh $(ARGS)

tap:
	./scripts/tap.sh $(ARGS)

clean:
	rm -rf .build build dist
