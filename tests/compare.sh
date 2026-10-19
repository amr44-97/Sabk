#!/usr/bin/env bash
# Differential test: `--tokens`, `--ast`, `--resolve` and `--types` on
# every .smelt file here (tests and std), with this compiler and with the
# C++ one it was ported from ($OLD, by default ../the-compiler/smelt,
# archived). Output and exit code must match, error messages included.
#
# usage: tests/compare.sh [--tokens|--ast|--resolve|--types]
#   (--tokens and --ast by default: since std's error enums, the C++
#   compiler can't compile what imports std, so the later modes only
#   compare the files that don't)

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
  tests/errors/log_format.smelt tests/run/format_directives.smelt
  tests/run/is_not.smelt tests/errors/is_not_bindings.smelt
  tests/run/keyword_fields.smelt tests/errors/keyword_field_binding.smelt
  tests/run/for_index.smelt tests/errors/for_index_assign.smelt
  tests/errors/for_index_twice.smelt tests/errors/for_index_range.smelt
  tests/run/let_typed.smelt tests/errors/let_typed_discard.smelt
  tests/errors/parse_let_values_type.smelt tests/run/variant_literal.smelt
  tests/errors/variant_literal_misuse.smelt tests/errors/variant_literal_dot.smelt
  tests/errors/parse_old_literals.smelt tests/run/null_pointer.smelt
  tests/run/option_wrap.smelt tests/errors/option_wrap.smelt
  tests/run/variant_access.smelt tests/errors/variant_access.smelt
  tests/errors/variant_access_run.smelt tests/errors/tagged_enum_misuse.smelt
  tests/run/error_enums.smelt tests/errors/error_enum_misuse.smelt
  tests/errors/error_enum_none.smelt tests/errors/error_type.smelt
  tests/errors/or_return_misuse.smelt tests/types/several_results.smelt
  tests/run/several_results.smelt std/io.smelt std/process.smelt std/str.smelt
  tests/errors/nodiscard.smelt tests/errors/or_return_placement.smelt
  tests/errors/void_results.smelt tests/run/error_type.smelt
  tests/run/error_values.smelt tests/run/nodiscard.smelt tests/run/void_results.smelt "

modes=("$@")
((${#modes[@]})) || modes=(--tokens --ast)
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
