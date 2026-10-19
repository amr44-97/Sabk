#!/usr/bin/env bash
# Golden-file tests. Each tests/<suite>/<name>.smelt is run through
# build/smelt and its output is compared with <name>.expected:
#
#   lexer/   smelt --tokens file   stdout, must exit 0
#   parser/  smelt --ast file      stdout, must exit 0
#   resolve/ smelt --resolve file  stdout (every module, names linked; with
#                                  tests/resolve/std), must exit 0
#   types/   smelt --types file    stdout (every module and instance, with
#                                  types; with tests/resolve/std), exit 0
#   errors/  smelt --resolve file  stderr, must exit non-zero (for now, the
#                                  errors up to the resolver's; std is ./std)
#
# usage: tests/run.sh [--update] [filter]
#   --update  rewrite the .expected files from the current output
#             (review the diff before committing them!)
#   filter    only run tests whose path contains this text

cd "$(dirname "$0")/.." || exit 1

update=0
filter=""
for arg in "$@"; do
  case "$arg" in
  --update) update=1 ;;
  *) filter="$arg" ;;
  esac
done

make -s build/smelt || exit 1

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
pass=0
fail=0

for src in tests/*/*.smelt; do
  [[ -n "$filter" && "$src" != *"$filter"* ]] && continue
  suite=$(basename "$(dirname "$src")")
  [[ "$suite" == unit ]] && continue   # `make unit`: checked by their own scripts
  expected="${src%.smelt}.expected"
  case "$suite" in
  lexer)  actual=$(build/smelt --tokens "$src" 2>&1); code=$?; ok=$((code == 0)) ;;
  parser) actual=$(build/smelt --ast "$src" 2>&1); code=$?; ok=$((code == 0)) ;;
  resolve) actual=$(build/smelt --resolve --std tests/resolve/std "$src" 2>&1); code=$?; ok=$((code == 0)) ;;
  types)  actual=$(build/smelt --types --std tests/resolve/std "$src" 2>&1); code=$?; ok=$((code == 0)) ;;
  errors) actual=$(build/smelt --resolve --std std "$src" 2>&1 >/dev/null); code=$?; ok=$((code != 0)) ;;
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
echo "$pass passed, $fail failed"
((fail == 0))
