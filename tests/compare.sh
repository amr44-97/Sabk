#!/usr/bin/env bash
# Differential test: `--tokens`, `--ast`, `--resolve` and `--types` on
# every .smelt file here (tests and std), with this compiler and with the
# C++ one it was ported from ($OLD, by default ../the-compiler/smelt,
# archived). Output and exit code must match, error messages included.
#
# usage: tests/compare.sh [--tokens|--ast|--resolve|--types]   (all by default)

cd "$(dirname "$0")/.." || exit 1
make -s smelt || exit 1

old=${OLD:-../the-compiler/smelt}
if [[ ! -x "$old" ]]; then
  echo "no C++ compiler at $old (set OLD=...)"
  exit 1
fi
# where this compiler means to differ: a macro's labels get its color, so
# they don't clash with its caller's (README.md), and the files that use
# what the language gained since the port (Smelt-language-plan.md)
known=" tests/resolve/macro_labels.smelt
  tests/errors/format_check.smelt tests/errors/format_directives.smelt
  tests/errors/log_format.smelt tests/run/format_directives.smelt "

modes=("$@")
((${#modes[@]})) || modes=(--tokens --ast --resolve --types)
same=0
differ=0
for mode in "${modes[@]}"; do
  for src in $(find tests std -name '*.smelt' | sort); do
    [[ " $(echo $known) " == *" $src "* ]] && continue
    extra=()
    [[ "$mode" == --resolve || "$mode" == --types ]] && extra=(--std std)
    want=$("$old" "$mode" "${extra[@]}" "$src" 2>&1); want_code=$?
    got=$(./smelt "$mode" "${extra[@]}" "$src" 2>&1); got_code=$?
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
