#!/usr/bin/env bash
# Differential test: `--tokens`, `--ast`, `--resolve` and `--types` on
# every .sabk file here (tests and std), with this compiler and with the
# C++ one it was ported from ($OLD, by default ../the-compiler/smelt,
# archived). Output and exit code must match, error messages included.
#
# usage: tests/compare.sh [--tokens|--ast|--resolve|--types]
#   (--tokens and --ast by default: since std's error enums, the C++
#   compiler can't compile what imports std, so the later modes only
#   compare the files that don't)

cd "$(dirname "$0")/.." || exit 1
make -s sabk || exit 1

old=${OLD:-../the-compiler/smelt}
if [[ ! -x "$old" ]]; then
  echo "no C++ compiler at $old (set OLD=...)"
  exit 1
fi
# where this compiler means to differ: a macro's labels get its color, so
# they don't clash with its caller's (README.md), and the files that use
# what the language gained since the port (Sabk-language-plan.md)
known=" tests/resolve/macro_labels.sabk
  tests/run/optional_parens.sabk tests/errors/parse_if_no_parens.sabk
  tests/errors/parse_for_no_parens.sabk
  tests/errors/format_check.sabk tests/errors/format_directives.sabk
  tests/errors/log_format.sabk tests/run/format_directives.sabk
  tests/run/is_not.sabk tests/errors/is_not_bindings.sabk
  tests/run/keyword_fields.sabk tests/errors/keyword_field_binding.sabk
  tests/run/for_index.sabk tests/errors/for_index_assign.sabk
  tests/errors/for_index_twice.sabk tests/errors/for_index_range.sabk
  tests/run/let_typed.sabk tests/errors/let_typed_discard.sabk
  tests/errors/parse_let_values_type.sabk tests/run/variant_literal.sabk
  tests/errors/variant_literal_misuse.sabk tests/errors/variant_literal_dot.sabk
  tests/errors/parse_old_literals.sabk tests/run/null_pointer.sabk
  tests/run/option_wrap.sabk tests/errors/option_wrap.sabk
  tests/run/variant_access.sabk tests/errors/variant_access.sabk
  tests/errors/variant_access_run.sabk tests/errors/tagged_enum_misuse.sabk
  tests/run/error_enums.sabk tests/errors/error_enum_misuse.sabk
  tests/errors/error_enum_none.sabk tests/errors/error_type.sabk
  tests/errors/or_return_misuse.sabk tests/types/several_results.sabk
  tests/run/several_results.sabk std/io.sabk std/process.sabk std/str.sabk
  tests/errors/nodiscard.sabk tests/errors/or_return_placement.sabk
  tests/errors/void_results.sabk tests/run/error_type.sabk
  tests/run/error_values.sabk tests/run/nodiscard.sabk tests/run/void_results.sabk "

modes=("$@")
((${#modes[@]})) || modes=(--tokens --ast)
same=0
differ=0
for mode in "${modes[@]}"; do
  for src in $(find tests std -name '*.sabk' | sort); do
    [[ " $(echo $known) " == *" $src "* ]] && continue
    extra=()
    [[ "$mode" == --resolve || "$mode" == --types ]] && extra=(--std std)
    want=$("$old" "$mode" "${extra[@]}" "$src" 2>&1); want_code=$?
    got=$(./sabk "$mode" "${extra[@]}" "$src" 2>&1); got_code=$?
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
