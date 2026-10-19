# The Smelt compiler in Smelt, built by the C++ one (stage 0) until it can
# build itself.
SMELT ?= ../the-compiler/smelt

build/smelt: $(wildcard src/*.smelt)
	@mkdir -p build
	$(SMELT) src/main.smelt -o build/smelt

test: build/smelt
	@tests/run.sh

# --tokens and --ast on every .smelt file in ../the-compiler, against stage 0's
compare: build/smelt
	@tests/compare.sh

clean:
	rm -rf build

.PHONY: test compare clean
