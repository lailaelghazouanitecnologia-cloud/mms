ZIG = zig
BUN = bun

.PHONY: all build test clean install

all: build

build:
	$(ZIG) build

test:
	$(ZIG) build test

clean:
	rm -rf zig-out zig-cache

install: build
	cp zig-out/bin/mms /usr/local/bin/

run:
	$(ZIG) build run -- $(ARGS)
