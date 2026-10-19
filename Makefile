# Smelt, a compiler written in Smelt. It builds itself: the first time from
# bootstrap/smelt.c, the C it writes for itself (a seed, for Linux x86-64;
# `make seed` refreshes it), and from then on `./smelt` builds `./smelt`.
CC ?= cc
C_FLAGS = -std=c11 -fwrapv -fno-strict-aliasing -w

smelt: build/stage0 $(wildcard src/*.smelt src/*.c)
	build/stage0 --std std src/main.smelt -o smelt

# the compiler from the seed: what builds the first ./smelt
build/stage0: bootstrap/smelt.c src/vm_ffi.c
	@mkdir -p build
	$(CC) $(C_FLAGS) -O2 -o build/stage0 bootstrap/smelt.c src/vm_ffi.c -lffi

test: smelt
	@tests/run.sh

# unit tests of single modules, checked against Python
unit: smelt
	@./smelt --run tests/unit/i128_test.smelt | python3 tests/unit/i128_check.py

# the dumps and messages, against the C++ compiler this one was ported
# from (../the-compiler, archived), on every .smelt file here
compare: smelt
	@tests/compare.sh

# the compiler builds itself, and that one builds itself again: both must
# write the same C for the compiler (a fixed point), which is the seed's
bootstrap: smelt
	./smelt --std std src/main.smelt -o build/smelt2
	build/smelt2 --std std src/main.smelt -o build/smelt3
	build/smelt2 --emit-c --std std src/main.smelt > build/smelt2.c
	build/smelt3 --emit-c --std std src/main.smelt > build/smelt3.c
	cmp build/smelt2.c build/smelt3.c && echo "fixed point: stage 2 and stage 3 write the same C"
	@cmp -s build/smelt2.c bootstrap/smelt.c && echo "and the seed is up to date" || echo "the seed is older: make seed"

# the seed: the C this compiler writes for itself
seed: smelt
	./smelt --emit-c --std std src/main.smelt > build/seed.c
	mv build/seed.c bootstrap/smelt.c

clean:
	rm -rf build smelt

.PHONY: test unit compare bootstrap seed clean
