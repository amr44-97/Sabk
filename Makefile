# Sabk, a compiler written in Sabk. It builds itself: the first time from
# bootstrap/sabk.c, the C it writes for itself (a seed, for Linux x86-64;
# `make seed` refreshes it), and from then on `./sabk` builds `./sabk`.
CC ?= cc
C_FLAGS = -std=c11 -fwrapv -fno-strict-aliasing -w

sabk: build/stage0 build/qbe $(wildcard src/*.sabk src/*.c std/*.sabk)
	build/stage0 --std std src/main.sabk -o sabk

# QBE (vendor/qbe), for --qbe: built here, out of its own directory
QBE_SRC = $(wildcard vendor/qbe/*.c vendor/qbe/amd64/*.c vendor/qbe/arm64/*.c vendor/qbe/rv64/*.c)

build/qbe: $(QBE_SRC) $(wildcard vendor/qbe/*.h vendor/qbe/*/*.h)
	@mkdir -p build/qbe_config
	@case `uname` in \
	*Darwin*) case `uname -m` in *arm64*) t=T_arm64_apple ;; *) t=T_amd64_apple ;; esac ;; \
	*) case `uname -m` in *aarch64*|*arm64*) t=T_arm64 ;; *riscv64*) t=T_rv64 ;; *) t=T_amd64_sysv ;; esac ;; \
	esac; echo "#define Deftgt $$t" > build/qbe_config/config.h
	$(CC) -std=c99 -O2 -w -Ibuild/qbe_config -o build/qbe $(QBE_SRC)

# the compiler from the seed: what builds the first ./sabk
build/stage0: bootstrap/sabk.c src/vm_ffi.c
	@mkdir -p build
	$(CC) $(C_FLAGS) -O2 -o build/stage0 bootstrap/sabk.c src/vm_ffi.c -lffi

test: sabk
	@tests/run.sh
	@tests/run.sh --interp

# only the run tests, through the VM (--interp) instead of the C
interp: sabk
	@tests/run.sh --interp

# only the run tests, built with the C written from the IR (--c-from-ir)
c-from-ir: sabk
	@tests/run.sh --c-from-ir

# only the run tests, built with QBE (--qbe)
qbe: sabk
	@tests/run.sh --qbe

# unit tests of single modules, checked against Python
unit: sabk
	@./sabk --run tests/unit/i128_test.sabk | python3 tests/unit/i128_check.py

# the compiler builds itself, and that one builds itself again: both must
# write the same C for the compiler (a fixed point), which is the seed's
bootstrap: sabk
	./sabk --std std src/main.sabk -o build/sabk2
	build/sabk2 --std std src/main.sabk -o build/sabk3
	build/sabk2 --emit-c --std std src/main.sabk > build/sabk2.c
	build/sabk3 --emit-c --std std src/main.sabk > build/sabk3.c
	cmp build/sabk2.c build/sabk3.c && echo "fixed point: stage 2 and stage 3 write the same C"
	@cmp -s build/sabk2.c bootstrap/sabk.c && echo "and the seed is up to date" || echo "the seed is older: make seed"

# the seed: the C this compiler writes for itself
seed: sabk
	./sabk --emit-c --std std src/main.sabk > build/seed.c
	mv build/seed.c bootstrap/sabk.c

clean:
	rm -rf build sabk

.PHONY: test interp c-from-ir qbe unit bootstrap seed clean
