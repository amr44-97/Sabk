# The Smelt compiler in Smelt, built by the C++ one (stage 0) until it can
# build itself.
SMELT ?= ../the-compiler/smelt

build/smelt: $(wildcard src/*.smelt)
	@mkdir -p build
	$(SMELT) src/main.smelt -o build/smelt

test: build/smelt
	@tests/run.sh

# unit tests of single modules, checked against Python
unit:
	@$(SMELT) --run tests/unit/i128_test.smelt | python3 tests/unit/i128_check.py

# --tokens and --ast on every .smelt file in ../the-compiler, against stage 0's
compare: build/smelt
	@tests/compare.sh

# the compiler builds itself, and that one builds itself again: both must
# write the same C for the compiler (a fixed point)
bootstrap: build/smelt
	build/smelt --std std src/main.smelt -o build/smelt2
	build/smelt2 --std std src/main.smelt -o build/smelt3
	build/smelt2 --emit-c --std std src/main.smelt > build/smelt2.c
	build/smelt3 --emit-c --std std src/main.smelt > build/smelt3.c
	cmp build/smelt2.c build/smelt3.c && echo "fixed point: stage 2 and stage 3 write the same C"

clean:
	rm -rf build

.PHONY: test unit compare bootstrap clean
