#!/usr/bin/env bash
# The C libraries tests bind with #library and #system_library, built
# before the tests run: #run calls into them while compiling, before any
# build step of the test's own could make them.
#   tests/run/lib/clib/build.sh <out-dir>
set -e
src="$(dirname "$0")"
out="$1"
mkdir -p "$out"
cc=${CC:-cc}
$cc -c -fPIC -o "$out/both.o" "$src/both.c"
ar rcs "$out/libsabk_both.a" "$out/both.o"
$cc -shared -fPIC -DSHARED -o "$out/libsabk_both.so" "$src/both.c" -lm
$cc -shared -fPIC -o "$out/libsabk_shared.so" "$src/shared.c"
cp "$out/libsabk_both.a" "$out/libsabk_static_only.a"
rm -f "$out/both.o"
