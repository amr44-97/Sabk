#!/usr/bin/env bash
# Golden-file tests. Each tests/<suite>/<name>.sabk is run through
# ./sabk and its output is compared with <name>.expected:
#
#   lexer/   sabk --tokens file   stdout, must exit 0
#   parser/  sabk --ast file      stdout, must exit 0
#   resolve/ sabk --resolve file  stdout (every module, names linked; with
#                                  tests/resolve/std), must exit 0
#   types/   sabk --types file    stdout (every module and instance, with
#                                  types; with tests/resolve/std), exit 0
#   warnings/ sabk --check file   stderr (the warnings), must exit 0
#   run/     sabk --run file      the program's output and exit code (with
#                                  ./std); a `// args: a b` line passes
#                                  arguments
#   errors/  sabk --emit-c file   stderr, must exit non-zero (std is ./std)
#
# usage: tests/run.sh [--update] [--interp] [filter]
#   --update  rewrite the .expected files from the current output
#             (review the diff before committing them!)
#   --interp  only run/, through `sabk --interp` (the VM) instead of
#             --run, against the same .expected files: the VM's lowering
#             must do what the C's does. A `// no-interp: why` line skips
#             a test the VM can't run.
#   filter    only run tests whose path contains this text

cd "$(dirname "$0")/.." || exit 1

update=0
interp=0
filter=""
for arg in "$@"; do
  case "$arg" in
  --update) update=1 ;;
  --interp) interp=1 ;;
  *) filter="$arg" ;;
  esac
done

make -s sabk || exit 1
# the C libraries tests bind (#library): built first, since #run calls into
# them while compiling
tests/run/lib/clib/build.sh build/test_libs || exit 1

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
pass=0
fail=0
skip=0

for src in tests/*/*.sabk; do
  [[ -n "$filter" && "$src" != *"$filter"* ]] && continue
  suite=$(basename "$(dirname "$src")")
  [[ "$suite" == unit ]] && continue   # `make unit`: checked by their own scripts
  if ((interp)); then
    [[ "$suite" != run ]] && continue
    if grep -q '^// no-interp:' "$src"; then
      skip=$((skip + 1))
      continue
    fi
  fi
  expected="${src%.sabk}.expected"
  case "$suite" in
  lexer)  actual=$(./sabk --quiet --tokens "$src" 2>&1); code=$?; ok=$((code == 0)) ;;
  parser) actual=$(./sabk --quiet --ast "$src" 2>&1); code=$?; ok=$((code == 0)) ;;
  resolve) actual=$(./sabk --quiet --resolve --std tests/resolve/std "$src" 2>&1); code=$?; ok=$((code == 0)) ;;
  types)  actual=$(./sabk --quiet --types --std tests/resolve/std "$src" 2>&1); code=$?; ok=$((code == 0)) ;;
  warnings) actual=$(./sabk --quiet --check --std std "$src" 2>&1); code=$?; ok=$((code == 0)) ;;
  errors) actual=$(./sabk --quiet --emit-c --std std "$src" 2>&1 >/dev/null); code=$?; ok=$((code != 0)) ;;
  run)    # a `// args: a b c` line gives the program its arguments (quoted
          # as in a shell)
          eval "args=($(grep -m1 '^// args:' "$src" | sed 's|^// args: *||'))"
          how=$( ((interp)) && echo --interp || echo --run )
          actual=$(./sabk --quiet "$how" --std std "$src" -- "${args[@]}" 2>&1); code=$?
          actual+=$'\n'"[exit $code]"; ok=1 ;;
  *) echo "unknown suite: $suite"; exit 1 ;;
  esac

  ((update)) && printf '%s\n' "$actual" > "$expected"

  if [[ ! -f "$expected" ]]; then
    echo "MISSING  $src (run with --update to create it)"
    fail=$((fail + 1))
  elif ((!ok)); then
    echo "FAIL     $src (unexpected exit code $code)"
    printf '%s\n' "$actual" | sed 's/^/         /' | head -20
    fail=$((fail + 1))
  elif ! diff -u "$expected" <(printf '%s\n' "$actual") > "$tmp"; then
    echo "FAIL     $src"
    sed 's/^/         /' "$tmp" | head -40
    fail=$((fail + 1))
  else
    pass=$((pass + 1))
  fi
done

echo
if ((interp)); then
  echo "$pass passed, $fail failed through --interp ($skip skipped: no-interp)"
else
  echo "$pass passed, $fail failed"
fi
((fail == 0))
