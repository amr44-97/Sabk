#!/usr/bin/env bash
# Differential test: `--tokens`, `--ast`, `--resolve` and `--types` on every .smelt file in
# ../the-compiler (its tests and std), with this compiler and with stage 0,
# the C++ one. Output and exit code must match, error messages included.
#
# usage: tests/compare.sh [--tokens|--ast|--resolve|--types]   (all by default)
#
# --resolve and --types use ./std (a link to ../the-compiler/std) for both, so the
# paths they print are the same.

cd "$(dirname "$0")/.." || exit 1
make -s build/smelt || exit 1

old=../the-compiler/smelt
modes=("$@")
((${#modes[@]})) || modes=(--tokens --ast --resolve --types)
same=0
differ=0
for mode in "${modes[@]}"; do
  for src in $(find ../the-compiler/tests ../the-compiler/std -name '*.smelt' | sort); do
    extra=()
    [[ "$mode" == --resolve || "$mode" == --types ]] && extra=(--std std)
    want=$("$old" "$mode" "${extra[@]}" "$src" 2>&1); want_code=$?
    got=$(build/smelt "$mode" "${extra[@]}" "$src" 2>&1); got_code=$?
    if [[ "$want" == "$got" && $want_code == $got_code ]]; then
      same=$((same + 1))
    else
      differ=$((differ + 1))
      echo "DIFFERS  $mode $src (exit $want_code, now $got_code)"
      diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | head -10 | sed 's/^/         /'
    fi
  done
done
echo
echo "$same the same, $differ different"
((differ == 0))
