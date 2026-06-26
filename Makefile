.PHONY: all build run clean

all: build

build:
	swift build

run:
	swift run

clean:
	rm -rf .build build dist
